#!/usr/bin/env node

const fs = require('fs');
const program = require('commander');
const { spawnSync } = require('child_process');
const csvWriter = require('csv-write-stream');
const ls = require('ls');
const path = require('path');

const readFile = (path) => fs.readFileSync(path, 'utf8').toString();

const opts = program
  .option('-c, --command <COMMAND>', 'command', 'spang2')
  .option('-n, --iteration <ITERATION_NUM>', 'number of iteration of measurement', 1)
  .option('-d, --delimiter <DELIMITER>', 'delimiter of output', '\t')
  .option('-e, --endpoint <ENDPOINT>', 'url of target endpoint')
  .option('-m, --method <METHOD>', 'method of HTTP requers (GET or POST)', 'GET')
  .option('-s, --skip_comparison', 'skip comparison with expected result')
  .option('-p, --pattern <REGEX>', 'extra constraint for file pattern specified in regex')
  .option('--sort', 'sort order of query result before validating')
  .option('--exclude <REGEX>', 'extra constraint for file pattern to be excluded specified in regex')
  .option('--sec', 'output in "sec" (default: in "ms")')
  .option('--output_error', 'output to stderr')
  .option('-a, --average', 'calculate average')
  .option('-v, --verbose', 'output progress to stderr')
  .arguments('[json_or_queries...]')
  .parse(process.argv)
  .opts();

if (program.args.length < 1) {
  program.help();
}

let benchmarks = [];
for (let arg of program.args) {
  if (arg.endsWith('.json')) {
    benchmarks = benchmarks.concat(JSON.parse(readFile(arg)));
    process.chdir(path.dirname(arg));
  } else {
    benchmarks.push({ query: arg });
  }
}

const pattern = opts.pattern ? new RegExp(opts.pattern) : null;
const exclude = opts.exclude ? new RegExp(opts.exclude) : null;

let header = ['name', 'time'];
if (opts.average) {
  header.push('average');
}
if (!opts.skip_comparison) {
  header.push('valid');
}

let writer = csvWriter({
  separator: opts.delimiter,
  newline: '\n',
  headers: header,
  sendHeaders: true
});
writer.pipe(process.stdout);

for (let benchmark of benchmarks) {
  const queries = ls(benchmark.query);
  if (queries.length === 0) {
    console.error(`Warning: Query "${benchmark.query}" is specified but no matched files are found.`);
  }
  for (let file of queries) {
    if (pattern && !file.full.match(pattern)) {
      continue;
    }
    if (exclude && file.full.match(exclude)) {
      continue;
    }
    let expected = null;
    const defaultExpectedName = file.full.replace(/\.[^/.]+$/, '') + '.txt';
    if (!opts.skip_comparison) {
      if (!benchmark.expected && fs.existsSync(defaultExpectedName)) {
        expected = readFile(defaultExpectedName);
      } else if (benchmark.expected) {
        let files = ls(benchmark.expected);
        const basename = path.basename(defaultExpectedName);
        if (files.length == 1) {
          expected = readFile(files[0].full);
        } else {
          const matched = files.find((file) => file.file === basename);
          if (matched) {
            expected = readFile(matched.full);
          }
        }
      }
    }
    measureQuery(file.full, expected, opts.sort || benchmark.sort);
  }
}
writer.end();

function normalize(result) {
  return result.split(/\r\n|\r|\n/).sort().join("\n");
}

function measureQuery(queryPath, expected, sort) {
  let row = { name: queryPath };
  let times = [];
  let validations = [];
  if (opts.verbose) {
    console.error(queryPath);
  }
  for (let i = 0; i < opts.iteration; i++) {
    let column = (i + 1).toString();
    if (opts.verbose) {
      console.error(`query: ${column}`);
    }
    let arguments = ['--time', queryPath, '--method', opts.method];
    if (opts.endpoint) {
      arguments = arguments.concat(['--endpoint', opts.endpoint]);
    }
    let result = spawnSync(opts.command, arguments, { maxBuffer: Infinity });
    if (result.status) {
      // error
      console.error(result.stderr.toString());
      times.push('null');
      validations.push('null');
    } else {
      if (expected == null) {
        validations.push('null');
      } else {
        let actual = result.stdout.toString();
        if(sort) {
          actual = normalize(actual);
          expected = normalize(expected);
        }
        if (actual === expected) {
          validations.push('true');
        } else {
          validations.push('false');
          if (opts.output_error) {
            console.error(result.stdout.toString());
          }
        }
      }
      let matched = result.stderr.toString().match(/(\d+)ms/);
      if (matched) {
        time = matched[1];
        if (opts.sec) {
          time = time / 1000;
        }
        times.push(time);
      } else {
        times.push('null');
      }
      if (opts.verbose) {
        console.error(`time: ${times[times.length - 1]}, valid: ${validations[validations.length - 1]}`);
      }
    }
  }
  row['time'] = times.join(',');
  if (!opts.skip_comparison) {
    row['valid'] = validations.join(',');
  }
  if (opts.average) {
    let validTimes = times.filter((time) => time !== 'null');
    const average = validTimes.map((t) => parseInt(t)).reduce((a, b) => a + b, 0) / validTimes.length;
    row['average'] = average.toString();
  }
  writer.write(row);
}
