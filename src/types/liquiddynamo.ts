export type IslandState = 'idle' | 'compact' | 'minimal' | 'expanded' | 'alert';

export type DisplayMode = 'notch' | 'floating';

export type ExpandedTab = 'media' | 'airpods' | 'shelf' | 'calendar' | 'system';

export type NoiseControlMode = 'anc' | 'transparency' | 'adaptive' | 'off';

export type AlertType = 'airpods' | 'battery' | 'volume' | 'brightness' | 'charger';

export interface CodeModuleInfo {
  id: string;
  name: string;
  path: string;
  category: 'core' | 'features' | 'rendering' | 'system' | 'docs';
  description: string;
  files: string[];
  swiftSnippet?: string;
  architecturalRole: string;
  invariants: string[];
}

export interface SpecDoc {
  id: string;
  title: string;
  subtitle: string;
  date: string;
  tags: string[];
  filePath: string;
  summary: string;
  content: string;
}
