"""Small toolkit for building stylized 3D device icons from signed-distance shapes.

Shapes are combined with smooth boolean operations, turned into triangle meshes with
marching cubes, decimated, snapped back onto the surface, shaded with true SDF normals,
and written as USDZ (UsdPreviewSurface materials) for SceneKit / RealityKit / Quick Look.
"""
import math
import os

import numpy as np
from skimage import measure
import fast_simplification
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt, UsdUtils

F32 = np.float32


# ----------------------------------------------------------------------------- math
def L(v):
    return np.sqrt((v * v).sum(-1))


def rotx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], F32)


def roty(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], F32)


def rotz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], F32)


def loc(P, pos, R=None):
    """Points expressed in the local frame of an object placed at pos, rotated by R."""
    q = P - np.asarray(pos, F32)
    return q if R is None else q @ R


# ----------------------------------------------------------------------------- shapes
def sphere(P, c, r):
    return L(P - np.asarray(c, F32)) - r


def ellipsoid(P, c, r):
    r = np.asarray(r, F32)
    p = P - np.asarray(c, F32)
    k0 = L(p / r)
    k1 = L(p / (r * r))
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def box_r(P, c, half, r):
    q = np.abs(P - np.asarray(c, F32)) - (np.asarray(half, F32) - r)
    return L(np.maximum(q, 0)) + np.minimum(q.max(-1), 0) - r


def slab_r(P, c, hxy, hz, corner, edge):
    """Rounded rectangle in XY (corner radius), extruded along Z, with rounded edges."""
    q = P - np.asarray(c, F32)
    cr = max(corner - edge, 1e-4)
    qx = np.abs(q[:, 0]) - (hxy[0] - edge) + cr
    qy = np.abs(q[:, 1]) - (hxy[1] - edge) + cr
    d2 = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - cr
    dz = np.abs(q[:, 2]) - (hz - edge)
    d = np.minimum(np.maximum(d2, dz), 0) + np.hypot(np.maximum(d2, 0), np.maximum(dz, 0))
    return d - edge


def _axis_perm(q, axis):
    if axis == 0:
        return q[:, [1, 0, 2]]
    if axis == 2:
        return q[:, [0, 2, 1]]
    return q


def cyl_r(P, c, R, h, r, axis=1):
    q = _axis_perm(P - np.asarray(c, F32), axis)
    d0 = np.hypot(q[:, 0], q[:, 2]) - (R - r)
    d1 = np.abs(q[:, 1]) - (h - r)
    return np.minimum(np.maximum(d0, d1), 0) + np.hypot(np.maximum(d0, 0), np.maximum(d1, 0)) - r


def torus(P, c, R, r, axis=1):
    q = _axis_perm(P - np.asarray(c, F32), axis)
    return np.hypot(np.hypot(q[:, 0], q[:, 2]) - R, q[:, 1]) - r


def capsule(P, a, b, r):
    a = np.asarray(a, F32)
    b = np.asarray(b, F32)
    pa = P - a
    ba = b - a
    h = np.clip((pa @ ba) / float(ba @ ba), 0, 1)
    return L(pa - ba[None, :] * h[:, None]) - r


def chain(P, pts, r):
    d = None
    for a, b in zip(pts[:-1], pts[1:]):
        c = capsule(P, a, b, r)
        d = c if d is None else np.minimum(d, c)
    return d


def bezier(p0, p1, p2, n=14):
    p0, p1, p2 = (np.asarray(x, F32) for x in (p0, p1, p2))
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t ** 2 * p2


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def top_y(sdf, x, z, lo=-30.0, hi=30.0):
    """Highest y on the surface of sdf above point (x, z)."""
    ys = np.linspace(hi, lo, 1201).astype(F32)
    P = np.stack([np.full_like(ys, x), ys, np.full_like(ys, z)], 1)
    d = sdf(P)
    i = int(np.argmax(d <= 0))
    if d[i] > 0 or i == 0:
        raise ValueError("no surface")
    a, b = float(ys[i - 1]), float(ys[i])
    for _ in range(30):
        m = 0.5 * (a + b)
        if sdf(np.array([[x, m, z]], F32))[0] <= 0:
            b = m
        else:
            a = m
    return 0.5 * (a + b)


# ----------------------------------------------------------------------------- materials
MATERIALS = {
    # name: color, metallic, roughness, emissive, opacity, clearcoat
    "white_gloss": ((0.93, 0.94, 0.95), 0.0, 0.16, (0, 0, 0), 1.0, 1.0),
    "soft_white": ((0.90, 0.91, 0.90), 0.0, 0.42, (0, 0, 0), 1.0, 0.0),
    "aluminum": ((0.80, 0.82, 0.84), 1.0, 0.30, (0, 0, 0), 1.0, 0.0),
    "titanium": ((0.60, 0.61, 0.62), 1.0, 0.36, (0, 0, 0), 1.0, 0.0),
    "graphite": ((0.17, 0.18, 0.20), 0.85, 0.36, (0, 0, 0), 1.0, 0.0),
    "black_gloss": ((0.015, 0.015, 0.02), 0.0, 0.12, (0, 0, 0), 1.0, 1.0),
    "black_matte": ((0.035, 0.035, 0.04), 0.0, 0.70, (0, 0, 0), 1.0, 0.0),
    "rubber": ((0.05, 0.05, 0.055), 0.0, 0.92, (0, 0, 0), 1.0, 0.0),
    "fabric": ((0.30, 0.32, 0.33), 0.0, 0.95, (0, 0, 0), 1.0, 0.0),
    "screen": ((0.01, 0.012, 0.02), 0.0, 0.06, (0.015, 0.09, 0.08), 1.0, 1.0),
    "lens": ((0.01, 0.015, 0.03), 0.0, 0.05, (0.0, 0.02, 0.05), 1.0, 1.0),
    "glass": ((0.55, 0.78, 0.72), 0.0, 0.04, (0, 0, 0), 0.35, 1.0),
    "smoke_glass": ((0.06, 0.08, 0.08), 0.0, 0.05, (0, 0, 0), 0.62, 1.0),
    "emerald": ((0.10, 0.90, 0.50), 0.0, 0.30, (0.08, 0.95, 0.52), 1.0, 0.0),
    "back_midnight": ((0.07, 0.13, 0.12), 0.0, 0.14, (0, 0, 0), 1.0, 1.0),
    "back_sage": ((0.46, 0.60, 0.52), 0.0, 0.30, (0, 0, 0), 1.0, 0.4),
    "paper": ((0.97, 0.97, 0.95), 0.0, 0.90, (0, 0, 0), 1.0, 0.0),
}


# ----------------------------------------------------------------------------- parts
class Part:
    def __init__(self, name, mat, sdf, lo, hi, voxel, tris):
        self.name, self.mat, self.sdf = name, mat, sdf
        self.lo, self.hi, self.voxel, self.tris = lo, hi, voxel, tris
        self.verts = self.faces = self.normals = None


def _grad(sdf, P, eps):
    g = np.empty_like(P)
    for i in range(3):
        o = np.zeros(3, F32)
        o[i] = eps
        g[:, i] = sdf(P + o) - sdf(P - o)
    n = np.maximum(L(g), 1e-9)[:, None]
    return g / n



def crease_fix(verts, faces, nrm, thresh_deg=35.0):
    """Per-corner normals: keep smooth SDF normals, but use the flat face normal where the
    two disagree strongly (large decimated flat faces next to rounded edges)."""
    v0, v1, v2 = verts[faces[:, 0]], verts[faces[:, 1]], verts[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    fn = fn / np.maximum(L(fn), 1e-12)[:, None]
    corner_v = faces.reshape(-1)
    vn = nrm[corner_v]
    fnr = np.repeat(fn, 3, axis=0)
    ok = (vn * fnr).sum(1) >= math.cos(math.radians(thresh_deg))
    cn = np.where(ok[:, None], vn, fnr).astype(F32)
    key = np.concatenate([corner_v[:, None].astype(np.int64), np.round(cn * 50).astype(np.int64)], axis=1)
    uniq, idx, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return verts[uniq[:, 0]].astype(F32), inv.reshape(-1, 3).astype(np.int32), cn[idx]


def build_part(part):
    v = part.voxel
    lo = np.asarray(part.lo, F32) - 2 * v
    hi = np.asarray(part.hi, F32) + 2 * v
    n = np.ceil((hi - lo) / v).astype(int) + 1
    xs = lo[0] + v * np.arange(n[0], dtype=F32)
    ys = lo[1] + v * np.arange(n[1], dtype=F32)
    zs = lo[2] + v * np.arange(n[2], dtype=F32)
    Y, Z = np.meshgrid(ys, zs, indexing="ij")
    YZ = np.stack([Y.ravel(), Z.ravel()], 1)
    per = max(1, 300000 // len(YZ))
    vol = np.empty(n, F32)
    for i0 in range(0, n[0], per):
        i1 = min(n[0], i0 + per)
        k = i1 - i0
        P = np.empty((k * len(YZ), 3), F32)
        P[:, 0] = np.repeat(xs[i0:i1], len(YZ))
        P[:, 1] = np.tile(YZ[:, 0], k)
        P[:, 2] = np.tile(YZ[:, 1], k)
        vol[i0:i1] = part.sdf(P).reshape(k, n[1], n[2])
    verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(v, v, v))
    verts = (verts + lo).astype(F32)
    faces = faces.astype(np.int32)
    if part.tris and len(faces) > part.tris:
        verts, faces = fast_simplification.simplify(
            verts, faces, target_reduction=1.0 - part.tris / len(faces))
        verts = verts.astype(F32)
        faces = faces.astype(np.int32)
    for _ in range(2):  # snap back onto the exact surface
        d = part.sdf(verts)
        g = _grad(part.sdf, verts, v * 0.5)
        verts = (verts - d[:, None] * g).astype(F32)
    nrm = _grad(part.sdf, verts, v * 0.5).astype(F32)
    fn = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
    vn = nrm[faces[:, 0]] + nrm[faces[:, 1]] + nrm[faces[:, 2]]
    if (fn * vn).sum() < 0:
        faces = faces[:, ::-1].copy()
    # make every triangle face outward (decimation can flip a few)
    v0, v1, v2 = verts[faces[:, 0]], verts[faces[:, 1]], verts[faces[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    vsum = nrm[faces[:, 0]] + nrm[faces[:, 1]] + nrm[faces[:, 2]]
    flip = (fn * vsum).sum(1) < 0
    faces = faces.copy()
    faces[flip] = faces[flip][:, ::-1]
    print(f"   {part.name}: fixed {int(flip.sum())} flipped triangles", flush=True) if flip.any() else None
    verts, faces, nrm = crease_fix(verts, faces, nrm)
    part.verts, part.faces, part.normals = verts, faces, nrm
    return part


def build_device(parts, pitch=0.0, yaw=0.0, size=1.0):
    for p in parts:
        build_part(p)
    R = roty(math.radians(yaw)) @ rotx(math.radians(pitch))
    allv = np.concatenate([p.verts @ R.T for p in parts])
    lo, hi = allv.min(0), allv.max(0)
    c = 0.5 * (lo + hi)
    s = size / float((hi - lo).max())
    for p in parts:
        p.verts = (((p.verts @ R.T) - c) * s).astype(F32)
        p.normals = (p.normals @ R.T).astype(F32)
    return parts


# ----------------------------------------------------------------------------- USDZ
def write_usdz(parts, out_dir, name):
    usdc = os.path.join(out_dir, f"{name}.usdc")
    usdz = os.path.join(out_dir, f"{name}.usdz")
    for f in (usdc, usdz):
        if os.path.exists(f):
            os.remove(f)
    stage = Usd.Stage.CreateNew(usdc)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    root = UsdGeom.Xform.Define(stage, "/Device")
    stage.SetDefaultPrim(root.GetPrim())
    made = {}
    for part in parts:
        if part.mat not in made:
            col, met, rough, emis, opac, coat = MATERIALS[part.mat]
            mp = f"/Device/Materials/{part.mat}"
            mat = UsdShade.Material.Define(stage, mp)
            sh = UsdShade.Shader.Define(stage, mp + "/Surface")
            sh.CreateIdAttr("UsdPreviewSurface")
            sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*col))
            sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(float(met))
            sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(float(rough))
            sh.CreateInput("emissiveColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*emis))
            sh.CreateInput("opacity", Sdf.ValueTypeNames.Float).Set(float(opac))
            sh.CreateInput("clearcoat", Sdf.ValueTypeNames.Float).Set(float(coat))
            sh.CreateInput("clearcoatRoughness", Sdf.ValueTypeNames.Float).Set(0.05)
            sh.CreateInput("ior", Sdf.ValueTypeNames.Float).Set(1.45)
            mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
            made[part.mat] = mat
        m = UsdGeom.Mesh.Define(stage, f"/Device/{part.name}")
        m.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(part.verts))
        m.CreateFaceVertexCountsAttr(Vt.IntArray.FromNumpy(np.full(len(part.faces), 3, np.int32)))
        m.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(part.faces.reshape(-1).astype(np.int32)))
        m.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(part.normals))
        m.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        m.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        m.CreateOrientationAttr(UsdGeom.Tokens.rightHanded)
        m.CreateDoubleSidedAttr(False)
        lo, hi = part.verts.min(0), part.verts.max(0)
        m.CreateExtentAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, lo)), Gf.Vec3f(*map(float, hi))]))
        UsdShade.MaterialBindingAPI.Apply(m.GetPrim()).Bind(made[part.mat])
    stage.GetRootLayer().Save()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(usdc), usdz)
    os.remove(usdc)
    return usdz


# ----------------------------------------------------------------------------- preview renderer
def _env(ry):
    top = np.array([0.88, 0.94, 0.96], F32)
    hor = np.array([0.56, 0.62, 0.62], F32)
    gnd = np.array([0.14, 0.16, 0.15], F32)
    t = np.clip(ry, -1, 1)[:, None]
    up = hor * (1 - t) + top * t
    dn = hor * (1 + t) - gnd * t
    return np.where(t >= 0, up, np.maximum(hor * (1 + t) + gnd * (-t) * 0 + gnd * (-t), 0))


def render(parts, size=520, ss=2, yaw=28.0, pitch=-14.0):
    W = H = size * ss
    R = rotx(math.radians(pitch)) @ roty(math.radians(yaw))
    pv = [p.verts @ R.T for p in parts]
    pn = [p.normals @ R.T for p in parts]
    allv = np.concatenate(pv)
    lo, hi = allv.min(0), allv.max(0)
    c = 0.5 * (lo + hi)
    scale = 0.80 * W / float((hi - lo)[:2].max())
    bgy = np.linspace(0, 1, H, dtype=F32)[:, None, None]
    img = (np.array([0.95, 0.96, 0.96], F32) * (1 - bgy) + np.array([0.82, 0.86, 0.85], F32) * bgy)
    img = np.repeat(img, W, axis=1).astype(F32)
    # soft ground shadow
    yy, xx = np.mgrid[0:H, 0:W].astype(F32)
    cx, cy = W / 2, H * 0.5 + (hi[1] - c[1]) * -scale * -1
    sy = H / 2 + (c[1] - lo[1]) * scale + H * 0.02
    sh = np.exp(-(((xx - W / 2) / (W * 0.26)) ** 2 + ((yy - sy) / (H * 0.03)) ** 2))
    img *= (1 - 0.22 * sh)[..., None]
    zbuf = np.full((H, W), -1e9, F32)
    L1 = np.array([-0.45, 0.75, 0.55], F32)
    L1 /= np.linalg.norm(L1)
    L2 = np.array([0.7, 0.15, 0.45], F32)
    L2 /= np.linalg.norm(L2)
    V = np.array([0, 0, 1], F32)

    def shade(n, mat):
        col, met, rough, emis, opac, coat = MATERIALS[mat]
        col = np.array(col, F32)
        n = n / np.maximum(L(n), 1e-6)[:, None]
        nv = np.clip(n @ V, 0, 1)
        d = np.clip(n @ L1, 0, 1)[:, None] * 0.85 + np.clip(n @ L2, 0, 1)[:, None] * 0.30 + 0.28
        r = 2 * nv[:, None] * n - V
        env = _env(r[:, 1])
        f0 = 0.04 * (1 - met) + met
        fres = (f0 + (1 - f0) * (1 - nv) ** 5)[:, None]
        sc = np.array([0.04] * 3, F32) * (1 - met) + col * met
        hv = L1 + V
        hv = hv / np.linalg.norm(hv)
        power = max(4.0, 2.0 / max(rough * rough, 1e-3) - 2.0)
        spec = np.clip(n @ hv, 0, 1)[:, None] ** power * (1.0 - 0.5 * rough)
        out = col * (1 - met) * d + env * sc * (0.55 + 0.9 * fres) * (1.0 - 0.6 * rough) + spec * (0.6 + 0.4 * met)
        if coat > 0:
            out = out + env * fres * 0.35 * coat
        out = out + np.array(emis, F32)
        return np.clip(out, 0, 1), opac

    order = sorted(range(len(parts)), key=lambda i: MATERIALS[parts[i].mat][4] < 1.0)
    for i in order:
        p = parts[i]
        v = pv[i]
        n = pn[i]
        sx = W / 2 + (v[:, 0] - c[0]) * scale
        sy_ = H / 2 - (v[:, 1] - c[1]) * scale
        sz = v[:, 2]
        opac = MATERIALS[p.mat][4]
        for f in p.faces:
            x0, x1, x2 = sx[f]
            y0, y1, y2 = sy_[f]
            minx = int(max(0, math.floor(min(x0, x1, x2))))
            maxx = int(min(W - 1, math.ceil(max(x0, x1, x2))))
            miny = int(max(0, math.floor(min(y0, y1, y2))))
            maxy = int(min(H - 1, math.ceil(max(y0, y1, y2))))
            if minx > maxx or miny > maxy:
                continue
            den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(den) < 1e-9 or den > 0:  # back-face culling (screen y points down)
                continue
            gx, gy = np.meshgrid(np.arange(minx, maxx + 1, dtype=F32) + 0.5,
                                 np.arange(miny, maxy + 1, dtype=F32) + 0.5)
            a = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / den
            b = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / den
            cc = 1 - a - b
            m = (a >= 0) & (b >= 0) & (cc >= 0)
            if not m.any():
                continue
            z = a * sz[f[0]] + b * sz[f[1]] + cc * sz[f[2]]
            zb = zbuf[miny:maxy + 1, minx:maxx + 1]
            m &= z > zb
            if not m.any():
                continue
            nn = (a[m][:, None] * n[f[0]] + b[m][:, None] * n[f[1]] + cc[m][:, None] * n[f[2]])
            col, _ = shade(nn, p.mat)
            sub = img[miny:maxy + 1, minx:maxx + 1]
            if opac < 1.0:
                sub[m] = sub[m] * (1 - opac) + col * opac
            else:
                sub[m] = col
                zb[m] = z[m]
    im = (np.clip(img, 0, 1) * 255).astype(np.uint8)
    from PIL import Image
    return Image.fromarray(im).resize((size, size), Image.LANCZOS)
