import fs from '@ohos.file.fs';

interface FileStatLike {
  isDirectory: () => boolean;
}

interface DirEntryLike {
  name: string;
}

type ListEntry = string | DirEntryLike;

export function sanitizeOfflineAreaName(name: string): string {
  const trimmed = name.trim();
  const safe = trimmed.replace(/[\\\/:*?"<>|]+/g, '_').replace(/\.\.+/g, '_');
  return safe.trim();
}

export function displayNameFromDir(dirName: string, prefix: string): string {
  if (dirName.startsWith(prefix)) {
    return dirName.slice(prefix.length);
  }
  return dirName;
}

export function fileExists(path: string): boolean {
  try {
    fs.statSync(path);
    return true;
  } catch {
    return false;
  }
}

export function dirExists(path: string): boolean {
  try {
    const stat: FileStatLike = fs.statSync(path) as FileStatLike;
    return stat && typeof stat.isDirectory === 'function' && stat.isDirectory();
  } catch {
    return false;
  }
}

export function deletePathRecursive(path: string): void {
  let stat: FileStatLike;
  try {
    stat = fs.statSync(path) as FileStatLike;
  } catch {
    return;
  }

  if (stat && typeof stat.isDirectory === 'function' && stat.isDirectory()) {
    try {
      const entries: ListEntry[] = fs.listFileSync(path) as ListEntry[];
      for (const raw of entries) {
        const entry: string = typeof raw === 'string' ? raw : raw?.name;
        if (!entry) {
          continue;
        }
        const childPath: string = entry.startsWith('/') ? entry : `${path}/${entry}`;
        deletePathRecursive(childPath);
      }
    } catch {
      // ignore
    }
    try {
      fs.rmdirSync(path);
    } catch {
      // ignore
    }
    return;
  }

  try {
    fs.unlinkSync(path);
  } catch {
    // ignore
  }
}

export function listOfflineMapDirs(rootDir: string, prefix: string): string[] {
  try {
    const entries: ListEntry[] = fs.listFileSync(rootDir) as ListEntry[];
    const dirs: string[] = [];
    for (const raw of entries) {
      const entry: string = typeof raw === 'string' ? raw : raw?.name;
      if (!entry) {
        continue;
      }
      if (!entry.startsWith(prefix)) {
        continue;
      }
      try {
        const stat: FileStatLike = fs.statSync(`${rootDir}/${entry}`) as FileStatLike;
        if (stat && typeof stat.isDirectory === 'function' && stat.isDirectory()) {
          dirs.push(entry);
        }
      } catch {
        // ignore bad entries
      }
    }
    dirs.sort();
    return dirs;
  } catch {
    return [];
  }
}
