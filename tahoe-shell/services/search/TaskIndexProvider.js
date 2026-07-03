.pragma library

function shouldRun(query) {
    var normalized = String(query || "").trim();
    if (normalized.length < 2)
        return false;

    var prefix = normalized.charAt(0);
    return prefix !== ">" && prefix !== "!" && prefix !== "=";
}

function results(query, limit, context) {
    var normalized = String(query || "").trim();
    if (normalized.length === 0 || context.cachedTaskQuery !== normalized)
        return [];

    var entries = context.cachedTaskEntries || [];
    var max = Math.max(1, limit || context.defaultLimit);
    var out = [];
    for (var i = 0; i < entries.length && out.length < max; i++) {
        var entry = entries[i] || {};
        var path = String(entry.path || "").trim();
        if (path.length === 0)
            continue;

        var kind = String(entry.kind || "recent-file");
        var folder = kind === "folder" || kind === "tracker-folder";
        var tracker = kind === "tracker-file" || kind === "tracker-folder";
        var title = String(entry.title || context.pathBasename(path) || path);
        var subtitle = String(entry.subtitle || (folder ? "文件夹" : "最近文件"));
        var score = context.scoreText(title, subtitle, [path], normalized, tracker ? 520 : (folder ? 540 : 560));
        if (score <= 0)
            continue;

        out.push(context.makeResult({
            "id": kind + ":" + path,
            "title": title,
            "subtitle": subtitle,
            "icon": context.iconPath("dock", folder ? "finder.png" : "notes.png"),
            "kind": folder ? "folder" : "recent-file",
            "provider": tracker ? "tracker" : (folder ? "folders" : "recent-files"),
            "score": score,
            "path": path
        }));
    }
    return out;
}

function parseOutput(text, context) {
    var entries = [];
    try {
        var parsed = JSON.parse(String(text || "[]"));
        var list = Array.isArray(parsed) ? parsed : [];
        for (var i = 0; i < list.length && entries.length < 80; i++) {
            var item = list[i] || {};
            var kind = String(item.kind || "");
            var path = String(item.path || "").trim();
            if ((kind === "recent-file" || kind === "folder" || kind === "tracker-file" || kind === "tracker-folder") && path.length > 0) {
                entries.push({
                    "kind": kind,
                    "path": path,
                    "title": String(item.title || context.pathBasename(path)),
                    "subtitle": String(item.subtitle || context.compactPath(path)),
                    "mtime": Number(item.mtime || 0)
                });
            }
        }
    } catch (e) {
        entries = [];
    }
    return entries;
}

function pythonSource() {
    return [
        "import datetime, json, os, shutil, subprocess, sys, time, urllib.parse, xml.etree.ElementTree as ET",
        "query = sys.argv[1].strip().lower() if len(sys.argv) > 1 else ''",
        "terms = [term for term in query.split() if term]",
        "deadline = time.monotonic() + 0.82",
        "home = os.path.expanduser('~')",
        "results = []",
        "seen = set()",
        "def expired():",
        "    return time.monotonic() > deadline",
        "def compact(path):",
        "    if home and path.startswith(home + os.sep):",
        "        return '~' + path[len(home):]",
        "    return path",
        "def matches(*values):",
        "    haystack = ' '.join(str(value or '').lower() for value in values)",
        "    return all(term in haystack for term in terms)",
        "def basename(path):",
        "    name = os.path.basename(path.rstrip(os.sep))",
        "    return name or path",
        "def stamp(value):",
        "    if not value:",
        "        return 0.0",
        "    try:",
        "        return datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()",
        "    except Exception:",
        "        return 0.0",
        "def add(kind, path, title, subtitle, mtime=0.0):",
        "    if expired():",
        "        return",
        "    path = os.path.abspath(os.path.expanduser(path))",
        "    if path in seen or not os.path.exists(path):",
        "        return",
        "    if kind == 'folder':",
        "        if not os.path.isdir(path):",
        "            return",
        "    elif not os.path.isfile(path):",
        "        return",
        "    title = str(title or basename(path)).strip()",
        "    subtitle = str(subtitle or compact(path)).strip()",
        "    if terms and not matches(title, subtitle, path):",
        "        return",
        "    seen.add(path)",
        "    results.append({'kind': kind, 'path': path, 'title': title, 'subtitle': subtitle, 'mtime': float(mtime or 0)})",
        "def bookmark_title(bookmark, fallback):",
        "    for child in list(bookmark):",
        "        if child.tag.rsplit('}', 1)[-1] == 'title' and child.text:",
        "            text = child.text.strip()",
        "            if text:",
        "                return text",
        "    return fallback",
        "def local_href_path(href):",
        "    parsed = urllib.parse.urlparse(href or '')",
        "    if parsed.scheme != 'file':",
        "        return ''",
        "    return urllib.parse.unquote(parsed.path or '')",
        "def add_recent_files():",
        "    xbel = os.path.join(home, '.local', 'share', 'recently-used.xbel')",
        "    try:",
        "        bookmarks = ET.parse(xbel).getroot().findall('.//{*}bookmark')",
        "    except Exception:",
        "        return",
        "    for bookmark in bookmarks[:450]:",
        "        if expired() or len(results) >= 80:",
        "            return",
        "        path = local_href_path(bookmark.attrib.get('href', ''))",
        "        if not path:",
        "            continue",
        "        title = bookmark_title(bookmark, basename(path))",
        "        mtime = stamp(bookmark.attrib.get('modified') or bookmark.attrib.get('visited') or bookmark.attrib.get('added'))",
        "        add('recent-file', path, title, '最近文件 · ' + compact(path), mtime)",
        "def tracker_line_path(line):",
        "    text = str(line or '').strip()",
        "    if not text or text.endswith(':'):",
        "        return ''",
        "    marker = text.find('file://')",
        "    if marker >= 0:",
        "        return local_href_path(text[marker:])",
        "    if text.startswith(os.sep):",
        "        return text",
        "    return ''",
        "def add_tracker_results():",
        "    if not terms or not shutil.which('tracker3'):",
        "        return",
        "    for flag, kind, label in (('--files', 'tracker-file', 'Tracker 文件'), ('--folders', 'tracker-folder', 'Tracker 文件夹')):",
        "        if expired() or len(results) >= 80:",
        "            return",
        "        remaining = max(0.05, deadline - time.monotonic())",
        "        try:",
        "            completed = subprocess.run(['tracker3', 'search', flag, '--limit', '24', query], capture_output=True, text=True, timeout=remaining, check=False)",
        "        except Exception:",
        "            continue",
        "        if completed.returncode != 0:",
        "            continue",
        "        for line in completed.stdout.splitlines():",
        "            if expired() or len(results) >= 80:",
        "                return",
        "            path = tracker_line_path(line)",
        "            if not path:",
        "                continue",
        "            try:",
        "                mtime = os.path.getmtime(path)",
        "            except Exception:",
        "                mtime = 0",
        "            add(kind, path, basename(path), label + ' · ' + compact(path), mtime)",
        "def configured_user_dirs():",
        "    paths = [home]",
        "    config = os.path.join(home, '.config', 'user-dirs.dirs')",
        "    try:",
        "        with open(config, 'r', encoding='utf-8', errors='ignore') as handle:",
        "            for line in handle:",
        "                line = line.strip()",
        "                if not line.startswith('XDG_') or '=' not in line:",
        "                    continue",
        "                value = line.split('=', 1)[1].strip().strip(chr(34))",
        "                value = value.replace('$HOME', home)",
        "                paths.append(os.path.expandvars(value))",
        "    except Exception:",
        "        pass",
        "    for name in ('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos', 'Templates', 'Public', 'Projects'):",
        "        paths.append(os.path.join(home, name))",
        "    unique = []",
        "    used = set()",
        "    for path in paths:",
        "        path = os.path.abspath(os.path.expanduser(path))",
        "        if path not in used and os.path.isdir(path):",
        "            used.add(path)",
        "            unique.append(path)",
        "    return unique",
        "def add_folders():",
        "    roots = configured_user_dirs()",
        "    for path in roots:",
        "        if expired() or len(results) >= 80:",
        "            return",
        "        add('folder', path, basename(path), '文件夹 · ' + compact(path), os.path.getmtime(path) if os.path.exists(path) else 0)",
        "    for base in roots[:7]:",
        "        if expired() or len(results) >= 80:",
        "            return",
        "        try:",
        "            with os.scandir(base) as entries:",
        "                for entry in entries:",
        "                    if expired() or len(results) >= 80:",
        "                        return",
        "                    try:",
        "                        if entry.is_dir(follow_symlinks=False):",
        "                            stat = entry.stat(follow_symlinks=False)",
        "                            add('folder', entry.path, entry.name, '文件夹 · ' + compact(entry.path), stat.st_mtime)",
        "                    except Exception:",
        "                        pass",
        "        except Exception:",
        "            pass",
        "add_recent_files()",
        "add_tracker_results()",
        "add_folders()",
        "results.sort(key=lambda item: (float(item.get('mtime') or 0), 1 if item.get('kind') == 'folder' else 0), reverse=True)",
        "print(json.dumps(results[:80], ensure_ascii=False))"
    ].join("\n");
}
