import { CanvasNode, CanvasEdge, Task, DocumentItem, AnalyticsMetric } from '../types';

export const INITIAL_CANVAS_NODES: CanvasNode[] = [
  {
    id: 'node-auth',
    title: 'Auth & Identity Gateway',
    description: 'OAuth2 session validation, RBAC enforcement & rate-limiting',
    type: 'service',
    x: 100,
    y: 180,
    status: 'active',
    tags: ['Go', 'JWT', 'Edge']
  },
  {
    id: 'node-api',
    title: 'Core API Orchestrator',
    description: 'GraphQL & REST unified endpoint router with trace telemetry',
    type: 'service',
    x: 440,
    y: 180,
    status: 'active',
    tags: ['Node.js', 'Fastify', 'v2.4']
  },
  {
    id: 'node-db',
    title: 'PostgreSQL Primary Cluster',
    description: 'Primary-replica cluster with automated connection pooling',
    type: 'database',
    x: 820,
    y: 100,
    status: 'active',
    tags: ['PG 16', 'PgBouncer', 'Read-Replica']
  },
  {
    id: 'node-cache',
    title: 'Redis Ephemeral Cache',
    description: 'Sub-millisecond query caching, session store and pub/sub',
    type: 'database',
    x: 820,
    y: 280,
    status: 'active',
    tags: ['Redis 7.2', 'Cluster']
  },
  {
    id: 'node-worker',
    title: 'Async Job Dispatcher',
    description: 'Distributed event queue for background compute and emails',
    type: 'service',
    x: 440,
    y: 390,
    status: 'active',
    tags: ['BullMQ', 'Worker Pool']
  },
  {
    id: 'node-decision',
    title: 'Multi-Region Routing',
    description: 'Evaluate latency vs data residency constraints for EU traffic',
    type: 'decision',
    x: 100,
    y: 390,
    status: 'in_review',
    tags: ['Infra', 'Compliance']
  },
  {
    id: 'node-analytics',
    title: 'Real-time Telemetry Sink',
    description: 'High-throughput event streaming with columnar aggregation',
    type: 'output',
    x: 820,
    y: 440,
    status: 'planned',
    tags: ['ClickHouse', 'Vector']
  }
];

export const INITIAL_CANVAS_EDGES: CanvasEdge[] = [
  { id: 'e-auth-api', source: 'node-auth', target: 'node-api', label: 'Authorized RPC' },
  { id: 'e-api-db', source: 'node-api', target: 'node-db', label: 'Read/Write Pool' },
  { id: 'e-api-cache', source: 'node-api', target: 'node-cache', label: 'Cache Lookup' },
  { id: 'e-api-worker', source: 'node-api', target: 'node-worker', label: 'Enqueue Job' },
  { id: 'e-decision-auth', source: 'node-decision', target: 'node-auth', label: 'Routing Policy', dashed: true },
  { id: 'e-worker-analytics', source: 'node-worker', target: 'node-analytics', label: 'Event Stream' }
];

export const INITIAL_TASKS: Task[] = [
  {
    id: 'TASK-101',
    title: 'Migrate connection pooler to PgBouncer v1.22',
    description: 'Upgrade PgBouncer config to support transaction-level pooling and tune max_client_conn parameters.',
    column: 'in_progress',
    priority: 'high',
    tags: ['Database', 'Infra'],
    dueDate: '2026-10-12',
    assignee: { name: 'Elena Rostova', initials: 'ER', color: 'bg-emerald-600' },
    checklist: [
      { id: 'c1', text: 'Benchmark staging pool under 2k rps load', done: true },
      { id: 'c2', text: 'Validate TLS certificate renewal hook', done: true },
      { id: 'c3', text: 'Rollout config change to secondary nodes', done: false },
      { id: 'c4', text: 'Verify p99 query latency stability', done: false }
    ],
    createdAt: '2026-10-01'
  },
  {
    id: 'TASK-102',
    title: 'Implement Webhook exponential retry with dead-letter queue',
    description: 'Ensure 3P partner webhook delivery failures back off predictably and route to DLQ after 5 attempts.',
    column: 'in_progress',
    priority: 'urgent',
    tags: ['API', 'Reliability'],
    dueDate: '2026-10-08',
    assignee: { name: 'Marcus Vance', initials: 'MV', color: 'bg-indigo-600' },
    checklist: [
      { id: 'c5', text: 'Create DLQ schema and retention policy', done: true },
      { id: 'c6', text: 'Implement jittered exponential backoff formula', done: true },
      { id: 'c7', text: 'Write end-to-end replay integration test', done: false }
    ],
    createdAt: '2026-10-02'
  },
  {
    id: 'TASK-103',
    title: 'Design audit log retention and S3 glacier archival pipeline',
    description: 'Compliance requirement: write cryptographic checksum for monthly compliance audit logs and transition to cold storage.',
    column: 'review',
    priority: 'medium',
    tags: ['Security', 'Compliance'],
    dueDate: '2026-10-15',
    assignee: { name: 'Sarah Chen', initials: 'SC', color: 'bg-amber-600' },
    checklist: [
      { id: 'c8', text: 'Draft lifecycle rule Terraform configuration', done: true },
      { id: 'c9', text: 'Validate SHA-256 manifest verification script', done: true }
    ],
    createdAt: '2026-10-03'
  },
  {
    id: 'TASK-104',
    title: 'Refactor OAuth token exchange to enforce PKCE on all clients',
    description: 'Deprecate legacy implicit flow and mandate S256 code challenge verification across public mobile and web clients.',
    column: 'done',
    priority: 'urgent',
    tags: ['Auth', 'Security'],
    dueDate: '2026-10-04',
    assignee: { name: 'Elena Rostova', initials: 'ER', color: 'bg-emerald-600' },
    checklist: [
      { id: 'c10', text: 'Update auth server endpoint to require code_verifier', done: true },
      { id: 'c11', text: 'Update client SDKs and release v3.1.0', done: true },
      { id: 'c12', text: 'Run regression test on mobile authentication', done: true }
    ],
    createdAt: '2026-09-28'
  },
  {
    id: 'TASK-105',
    title: 'Profile memory leak in long-lived SSE connections',
    description: 'Investigate heap growth during high socket churn on edge notifications proxy.',
    column: 'backlog',
    priority: 'high',
    tags: ['Performance', 'Edge'],
    dueDate: '2026-10-18',
    assignee: { name: 'Devon Lee', initials: 'DL', color: 'bg-violet-600' },
    checklist: [
      { id: 'c13', text: 'Capture heap snapshot before and after 10k connections', done: false },
      { id: 'c14', text: 'Isolate event listener cleanup on socket disconnect', done: false }
    ],
    createdAt: '2026-10-04'
  },
  {
    id: 'TASK-106',
    title: 'Add OpenTelemetry spans to payment reconciliation pipeline',
    description: 'Instrument stripe webhook ingestion and database write transactions with distributed trace context.',
    column: 'backlog',
    priority: 'medium',
    tags: ['Observability', 'Payments'],
    dueDate: '2026-10-22',
    assignee: { name: 'Marcus Vance', initials: 'MV', color: 'bg-indigo-600' },
    checklist: [
      { id: 'c15', text: 'Define custom span attributes for transaction ID', done: false }
    ],
    createdAt: '2026-10-05'
  }
];

export const INITIAL_DOCUMENTS: DocumentItem[] = [
  {
    id: 'doc-arch-rfc',
    title: 'RFC-042: Distributed Cache Invalidation Architecture',
    category: 'RFCs',
    starred: true,
    updatedAt: '2026-10-04T18:30:00Z',
    content: `# RFC-042: Distributed Cache Invalidation Architecture

**Status**: Under Team Review  
**Author**: Marcus Vance & Elena Rostova  
**Target Release**: Q4 2026 Infrastructure Milestone  

---

## 1. Problem Statement

Under high write concurrency, secondary replicas experience up to 180ms replication lag. Clients requesting resources immediately after mutations currently risk receiving stale cached responses from regional edge caches.

## 2. Proposed Architecture

We propose adopting an **Event-Driven Write-Through Invalidation** pattern utilizing Redis Pub/Sub combined with CDC (Change Data Capture) via Debezium:

1. **Transactional Mutation**: Postgres writes transaction commit with WAL sequence.
2. **CDC Connector**: Debezium captures row-level mutation event in < 8ms.
3. **Broadcast Invalidation**: Event bus publishes invalidation message keyed by \`entity:tenant:id\`.
4. **Edge Interceptor**: Edge reverse proxy invalidates cached surrogate keys immediately.

\`\`\`typescript
interface InvalidationMessage {
  entityType: 'workspace' | 'task' | 'user';
  entityId: string;
  tenantId: string;
  walCommitEpoch: number;
  invalidatedKeys: string[];
}
\`\`\`

## 3. Benchmarks & SLOs

- **P95 Invalidation Latency**: < 22ms globally across 4 regions
- **Network Overhead**: < 450 bytes per event payload
- **Cache Hit Ratio Preservation**: Expected improvement from 91.2% to 97.8%

## 4. Rollout Strategy

- [x] Phase 1: Deploy test harness on canary cluster
- [ ] Phase 2: Dual-run invalidation in shadow mode
- [ ] Phase 3: Route 100% tenant traffic to unified invalidator
`
  },
  {
    id: 'doc-sprint-goals',
    title: 'Sprint 34: Core Reliability & Edge Performance',
    category: 'Specs',
    starred: true,
    updatedAt: '2026-10-03T11:15:00Z',
    content: `# Sprint 34: Core Reliability & Edge Performance

**Duration**: Oct 06 – Oct 20, 2026  
**Sprint Lead**: Sarah Chen  
**Story Points Committed**: 48 pts  

---

## Key Objectives

1. **P99 Latency Reduction**: Lower global API p99 response times below 140ms by pre-warming query execution plans.
2. **Zero Unhandled Webhook Failures**: Ship DLQ exponential backoff processor.
3. **Security Hardening**: Complete full PKCE verification on all public OAuth endpoints.

## Milestone Checkpoints

- **Mid-Sprint Review**: Oct 13, 2026
- **Code Freeze**: Oct 18, 2026 @ 17:00 UTC
- **Production Deployment Window**: Oct 20, 2026 @ 02:00 UTC
`
  },
  {
    id: 'doc-api-guide',
    title: 'Engineering Standards: REST & Event Conventions',
    category: 'Guides',
    starred: false,
    updatedAt: '2026-09-29T14:20:00Z',
    content: `# Engineering Standards: REST & Event Conventions

Standard operating guidelines for microservices and API interfaces across Stratos Studio.

### HTTP Status Code Contracts

- \`200 OK\`: Standard response with body payload
- \`201 Created\`: Successful resource creation with \`Location\` header
- \`204 No Content\`: Successful update/delete with empty body
- \`400 Bad Request\`: Structural validation error with RFC-7807 problem details
- \`409 Conflict\`: Optimistic concurrency lock collision (ETag mismatch)
- \`429 Too Many Requests\`: Rate limit reached with \`Retry-After\` header

### Error Response Schema

All errors follow the RFC-7807 structured format:

\`\`\`json
{
  "type": "https://api.stratos.dev/errors/concurrency-conflict",
  "title": "Resource Modified By Concurrent Transaction",
  "status": 409,
  "detail": "The document version (rev 14) is superseded by revision 15.",
  "instance": "/workspaces/ws-991/tasks/task-102"
}
\`\`\`
`
  }
];

export const INITIAL_ANALYTICS: AnalyticsMetric[] = [
  { id: 'm1', date: '2026-08-25', sprint: 'Sprint 29', velocity: 38, completedTasks: 24, prMerged: 31, testPassRate: 99.1, responseTimeMs: 165 },
  { id: 'm2', date: '2026-09-08', sprint: 'Sprint 30', velocity: 42, completedTasks: 28, prMerged: 36, testPassRate: 99.4, responseTimeMs: 152 },
  { id: 'm3', date: '2026-09-22', sprint: 'Sprint 31', velocity: 45, completedTasks: 31, prMerged: 42, testPassRate: 99.2, responseTimeMs: 144 },
  { id: 'm4', date: '2026-10-06', sprint: 'Sprint 32', velocity: 51, completedTasks: 36, prMerged: 49, testPassRate: 99.8, responseTimeMs: 128 },
  { id: 'm5', date: '2026-10-20', sprint: 'Sprint 33', velocity: 54, completedTasks: 39, prMerged: 53, testPassRate: 99.9, responseTimeMs: 119 }
];
