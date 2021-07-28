const parser = require('./template_parser');
const fs = require('fs');
const expandHomeDir = require('expand-home-dir');

let traverse = (o, fn) => {
  for (const i in o) {
    fn.apply(this, [i, o[i]]);
    if (o[i] !== null && typeof o[i] == 'object') {
      traverse(o[i], fn);
    }
  }
};

let prefixMap = {};
let urlToPrefix = {};
let orderedPrefixURLs;

readPrefixFile = (contents) => {
  contents.split('\n').forEach((line) => {
    tokens = line.split(/\s+/);
    if (
      tokens.length == 3 &&
      tokens[0] == 'PREFIX' &&
      tokens[1].endsWith(':') &&
      tokens[2].startsWith('<') &&
      tokens[2].endsWith('>')
    ) {
      const prefixName = tokens[1].substr(0, tokens[1].length - 1);
      prefixMap[prefixName] = line;
      urlToPrefix[tokens[2].substring(1, tokens[2].length - 2)] = prefixName;
    }
  });
};

exports.loadPrefixFile = (filePath) => {
  if (/^(http|https):\/\//.test(filePath)) {
    const syncRequest = require('sync-request');
    readPrefixFile(syncRequest('GET', filePath).getBody('utf8'));
  } else {
    filePath = expandHomeDir(filePath);
    if (fs.existsSync(filePath)) {
      readPrefixFile(fs.readFileSync(filePath, 'utf8'));
    }
  }
};

exports.setPrefixFiles = (filePaths) => {
  filePaths.forEach((filePath) => {
    exports.loadPrefixFile(filePath);
  });
};

exports.searchPrefix = (prefixName) => {
  return prefixMap[prefixName];
};

exports.insertUndefinedPrefixes = (sparql) => {
  const parsedQuery = parser.parse(sparql);
  const definedPrefixes = parsedQuery.prologue.prefixes.map((def) => def.prefix);
  prefixes = [];
  traverse(parsedQuery, (key, value) => {
    if (
      value &&
      value.token == 'uri' &&
      value.prefix &&
      !prefixes.includes(value.prefix) &&
      !definedPrefixes.includes(value.prefix)
    ) {
      prefixes.push(value.prefix);
    }
  });

  if (prefixes.length > 0) {
    const prologue = sparql.substr(0, parsedQuery.body.location.start.offset);
    const lastNewLineMatch = prologue.match(/\n\s+$/);
    const locationToInsert = lastNewLineMatch
      ? prologue.lastIndexOf(prologue.match(/\n\s+$/).pop()) + 1
      : parsedQuery.body.location.start.offset;
    sparql = sparql.insert(
      locationToInsert,
      prefixes.map((pre) => exports.searchPrefix(pre)).join('\n') + (lastNewLineMatch ? '\n' : '\n\n')
    );
  }
  return sparql;
};

exports.abbreviateURL = (srcUrl) => {
  if (!orderedPrefixURLs) {
    orderedPrefixURLs = Object.keys(urlToPrefix).sort((a, b) => -(a.length - b.length));
  }
  for (const url of orderedPrefixURLs) {
    if (srcUrl.startsWith(url)) {
      return `${urlToPrefix[url]}:${srcUrl.substring(url.length + 1)}`;
    }
  }
  return `<${srcUrl}>`;
};

expandPrefix = (prefix) => {
  const line = prefixMap[prefix];
  if (line) {
    const tokens = line.split(/\s+/);
    if (
      tokens.length == 3 &&
      tokens[0] == 'PREFIX' &&
      tokens[1].endsWith(':') &&
      tokens[2].startsWith('<') &&
      tokens[2].endsWith('>')
    ) {
      const expanded = tokens[2].substring(1, tokens[2].length - 1);
      return expanded;
    }
  }
};

exports.expandPrefixedUri = (arg) => {
  let matched;

  matched = arg.match(/^https:\/\/github.com\/([^\/]+)\/([^\/]+)\/blob\/(.+)/);
  if (matched) {
    const [, user, repository, version_file] = matched;
    return `https://raw.githubusercontent.com/${user}/${repository}/${version_file}`;
  }

  if (/^https?:\/\//.test(arg)) {
    return arg;
  }

  matched = arg.match(/^(\S+?)@github:([^\/]+)\/([^\/]+)\/(.+)/);
  if (matched) {
    const [, version, user, repository, file] = matched;
    return `https://raw.githubusercontent.com/${user}/${repository}/${version}/${file}`;
  }

  matched = arg.match(/^github@([^\/]+)\/([^\/]+)\/([^\/]+)\/(.+)/);
  if (matched) {
    const [, user, repository, version, file] = matched;
    return `https://raw.githubusercontent.com/${user}/${repository}/${version}/${file}`;
  }

  matched = arg.match(/^github:([^\/]+)\/([^\/]+)\/(.+)@(\S+?)$/);
  if (matched) {
    const [, user, repository, file, version] = matched;
    return `https://raw.githubusercontent.com/${user}/${repository}/${version}/${file}`;
  }

  matched = arg.match(/^(\w+):(.*)$/);
  if (matched) {
    const [, prefix, suffix] = matched;
    return expandPrefix(prefix) + suffix;
  }

  return expandPrefix(arg);
};
