let output;
let comments;
let currentIndent;
let indentUnit = '  ';

exports.format = (syntaxTree, indentDepth = 2) => {
  indentUnit = ' '.repeat(indentDepth);

  output = [];
  comments = syntaxTree.comments;
  currentIndent = '';

  if (syntaxTree.headers) {
    addLine(syntaxTree.headers.join(''));
  }
  if (syntaxTree.prologue?.length) {
    syntaxTree.prologue.forEach((p) => {
      if (p.base) {
        addLine(`BASE <${p.base}>`);
      } else {
        addLine(`PREFIX ${p.prefix || ''}: <${p.iri}>`);
      }
    });
    addLine('');
  }

  syntaxTree.functions?.forEach(addFunction);

  if (syntaxTree.queryBody?.select) {
    addSelect(syntaxTree.queryBody);
  } else if (syntaxTree.queryBody?.type === 'construct') {
    addConstruct(syntaxTree.queryBody);
  } else if (syntaxTree.queryBody?.type === 'ask') {
    addAsk(syntaxTree.queryBody);
  } else if (syntaxTree.queryBody?.type === 'describe') {
    addDescribe(syntaxTree.queryBody);
  } else if (syntaxTree.units) {
    for (let i = 0; i < syntaxTree.units.length; i++) {
      if (i > 0) {
        output[output.length - 1] += " ;\n";
      }
      addUnit(syntaxTree.units[i]);
    }
  }
  if (syntaxTree.values) {
    addInlineData(syntaxTree.values);
  }

  while (comments && comments.length) {
    output[output.length - 1] += comments.shift().text;
  }

  return output.join('\n');
};

const debugPrint = (object) => {
  console.log(JSON.stringify(object, undefined, 2));
};

const increaseIndent = (depth = 1) => {
  currentIndent += indentUnit.repeat(depth);
};

const decreaseIndent = (depth = 1) => {
  currentIndent = currentIndent.substr(0, currentIndent.length - indentUnit.length * depth);
};

const addLine = (line) => {
  output.push(currentIndent + line);
};

const addLineWithComment = (line, pos) => {
  while (comments && comments.length && comments[0].pos < pos) {
    output[output.length - 1] += comments.shift().text;
  }
  addLine(line);
};

const addAsk = (query) => {
  addLine('ASK {');
  increaseIndent();
  query.where.graphPattern.forEach(addPattern);
  decreaseIndent();
  addLine('}');
  addSolutionModifier(query);
}

const addDescribe = (query) => {
  const elems = query.value.map(getTripleElem).join(' ');
  addLine(`DESCRIBE ${elems}`);
  addDataset(query.from);
  if (query.where) {
    addLine('WHERE {');
    increaseIndent();
    query.where.graphPattern.forEach(addPattern);
    decreaseIndent();
    addLine('}');
  }
  addSolutionModifier(query);
}

const addUnit = (unit) => {
  if (unit.type === 'insertdata') {
    addLine('INSERT DATA {');
    increaseIndent();
    addTriples(unit.insert);
    decreaseIndent();
    addLine('}');
  } else if (unit.type === 'deletedata') {
    addLine('DELETE DATA {');
    increaseIndent();
    addTriples(unit.delete);
    decreaseIndent();
    addLine('}');
  } else if (unit.type === 'deletewhere') {
    addLine('DELETE WHERE {');
    increaseIndent();
    addTriples(unit.delete);
    decreaseIndent();
    addLine('}');
  } else if (unit.type === 'modify') {
    if (unit.with) {
      addLine(`WITH ${getTripleElem(unit.with)}`);
    }
    if (unit.delete) {
      addLine('DELETE {');
      increaseIndent();
      addTriples(unit.delete);
      decreaseIndent();
      addLine('}');
    }
    if (unit.insert) {
      addLine('INSERT {');
      increaseIndent();
      addTriples(unit.insert);
      decreaseIndent();
      addLine('}');
    }
    if (unit.using) {
      addLine(`USING ${getUsing(unit.using[0])}`);
    }
    addLine('WHERE {');
    increaseIndent();
    unit.where.graphPattern.forEach(addPattern);
    decreaseIndent();
    addLine('}');
  } else if (unit.type === 'add') {
    const g1 = getGraphOrDefault(unit.graphs[0]);
    const g2 = getGraphOrDefault(unit.graphs[1]);
    let silent = ' ';
    if (unit.silent) {
      silent = ' SILENT ';
    }
    addLine(`ADD${silent}${g1} TO ${g2}`);
  } else if (unit.type === 'move') {
    const g1 = getGraphOrDefault(unit.graphs[0]);
    const g2 = getGraphOrDefault(unit.graphs[1]);
    let silent = ' ';
    if (unit.silent) {
      silent = ' SILENT ';
    }
    addLine(`MOVE${silent}${g1} TO ${g2}`);
  } else if (unit.type === 'copy') {
    const g1 = getGraphOrDefault(unit.graphs[0]);
    const g2 = getGraphOrDefault(unit.graphs[1]);
    let silent = ' ';
    if (unit.silent) {
      silent = ' SILENT ';
    }
    addLine(`COPY${silent}${g1} TO ${g2}`);
  } else if (unit.type === 'load') {
    let silent = ' ';
    if (unit.silent) {
      silent = ' SILENT ';
    }
    addLine(`LOAD${silent}${getUri(unit.sourceGraph)}`);
  } else if (unit.type === 'clear') {
    let silent = ' ';
    if (unit.silent) {
      silent = ' SILENT ';
    }
    addLine(`CLEAR${silent}${getGraphRefAll(unit.destinyGraph)}`);
  } else if (unit.type === 'drop') {
    let silent = ' ';
    if (unit.silent) {
      silent = ' SILENT ';
    }
    addLine(`DROP${silent}${getGraphRefAll(unit.destinyGraph)}`);
  } else if (unit.type === 'create') {
    let silent = ' ';
    if (unit.silent) {
      silent = ' SILENT ';
    }
    addLine(`CREATE${silent}GRAPH ${getUri(unit.destinyGraph)}`);
  }
};

const getUsing = (graph) => {
  if (graph.kind === 'default') {
    return getUri(graph.uri);
  } else if (graph.kind === 'named') {
    return `NAMED ${getUri(graph.uri)}`;
  }
};

const getGraphOrDefault = (graph) => {
  if (graph === 'default') {
    return 'DEFAULT';
  } else {
    return getUri(graph);
  }
};

const getGraphRefAll = (graph) => {
  if (graph === 'default') {
    return 'DEFAULT';
  } else if (graph === 'named') {
    return 'NAMED';
  } else if (graph === 'all') {
    return 'ALL';
  } else {
    return `GRAPH ${getUri(graph)}`;
  }
};

const addSelect = (query) => {
  const vars = query.select;
  const lastVar = vars[vars.length-1];
  const pos = vars[0].value ? vars[0].value.location.start.offset : vars[0].location.start.offset;
  let endPos = lastVar.value ? lastVar.value.location.end.offset : lastVar.location.end.offset;

  addLineWithComment(getSelectClause(query), pos);

  const datasetEndPos= addDataset(query.from);
  if (datasetEndPos > endPos) {
    endPos = datasetEndPos;
  }

  addLineWithComment('WHERE {', endPos+1);
  increaseIndent();
  query.where.graphPattern.forEach(addPattern);
  decreaseIndent();
  addLineWithComment('}', query.where.location.end.offset);

  addSolutionModifier(query);
};

const addDataset = (dataset) => {
  if (dataset) {
    let endPos;
    dataset.forEach((d) => {
      if (d.graph) {
        endPos = addFrom(d.graph);
      } else if (d.namedGraph) {
        endPos = addFromNamed(d.namedGraph);
      }
    });
    return endPos;
  }
}

const addSolutionModifier = (query) => {
  if (query.group) {
    addLine('GROUP BY ' + query.group.map(elem => getTripleElem(elem)).join(' '));
  }
  if (query.having) {
    addLine(`HAVING ${getExpression(query.having[0])}`);
  }
  if (query.orderBy) {
    addLine('ORDER BY ' + getOrderClause(query.orderBy));
  }
  query.limitOffset?.forEach((lo) => {
    if (lo.limit) {
      addLine(`LIMIT ${lo.limit}`);
    } else if (lo.offset) {
      addLine(`OFFSET ${lo.offset}`);
    }
  });
}

const addConstruct = (query) => {
  if (query.template) {
    addLineWithComment('CONSTRUCT {', query.location.start.offset);
    increaseIndent();
    addTriples(query.template.triplePattern);
    decreaseIndent();
    addLine('}');
  } else {
    addLine('CONSTRUCT');
  }

  addDataset(query.from);

  addLine('WHERE {');
  increaseIndent();
  query.where.graphPattern.forEach(addPattern);
  decreaseIndent();
  addLine('}');

  addSolutionModifier(query);
};

const addFrom = (graph) => {
  const uri = getUri(graph);
  if (uri != null) {
    const pos = graph.location.start.offset;
    const endPos = graph.location.end.offset;
    addLineWithComment('FROM ' + uri, pos);
    return endPos;
  }
};

const addFromNamed = (graph) => {
  const uri = getUri(graph);
  if (uri != null) {
    const pos = graph.location.start.offset;
    const endPos = graph.location.end.offset;
    addLineWithComment('FROM NAMED ' + uri, pos);
    return endPos;
  }
};

const addGGP = (pattern) => {
  addLine('{');
  increaseIndent();
  if (pattern.type === 'select') {
    addSelect(pattern);
    if (pattern.values) {
      addInlineData(pattern.values);
    }
  } else {
    pattern.graphPattern.forEach(addPattern);
  }
  decreaseIndent();
  addLine('}');
};

const addPattern = (pattern) => {
  if (pattern.graphPattern || pattern.type === 'select') {
    addGGP(pattern);
    return;
  }
  if (pattern.data) {
    addInlineData(pattern);
    return;
  }
  if (pattern.triplePattern) {
    addTriples(pattern.triplePattern);
  }
  switch (pattern.token) {
    case 'filter':
      addFilter(pattern);
      break;
    case 'bind':
      addLine(`BIND (${getExpression(pattern.expression)} AS ${getVar(pattern.as)})`);
      break;
    case 'graphgraphpattern':
      addLine(`GRAPH ${getTripleElem(pattern.graph)} {`);
      increaseIndent();
      pattern.value.graphPattern.forEach(addPattern);
      decreaseIndent();
      addLine('}');
      break;
    case 'unionpattern':
      for (let i = 0; i < pattern.value.length; i++) {
        if (i > 0) {
          addLine('UNION');
        }
        addGGP(pattern.value[i]);
      }
      break;
    case 'optionalgraphpattern':
      addLine('OPTIONAL {');
      increaseIndent();
      pattern.value.graphPattern.forEach(addPattern);
      decreaseIndent();
      addLine('}');
      break;
    case 'servicegraphpattern':
      addLine(`SERVICE ${getTripleElem(pattern.value[0])}`);
      addGGP(pattern.value[1]);
      break;
    case 'minusgraphpattern':
      addLine('MINUS {');
      increaseIndent();
      pattern.value.graphPattern.forEach(addPattern);
      decreaseIndent();
      addLine('}');
      break;
    case 'functioncall':
      const args = pattern.args.map(getExpression).join(', ');
      addLine(getUri(pattern.iriref) + `(${args})`);
      break;
  }
};

const getOrderClause = (conditions) => {
  let orderConditions = [];
  conditions.forEach((condition) => {
    let oc;
    if (condition.by.variable) {
      oc = getVar(condition.by);
    } else {
      oc = getExpression(condition.by);
    }
    if (condition.order === 'ASC') {
      orderConditions.push(`ASC(${oc})`);
    } else if (condition.order === 'DESC') {
      orderConditions.push(`DESC(${oc})`);
    } else {
      orderConditions.push(oc);
    }
  });

  return orderConditions.join(' ');
};

const getSelectClause = (query) => {
  let select = 'SELECT ';
  if (query.modifier) {
    select += `${query.modifier.toString()} `;
  }
  select += query.select.map(getSelectVar).join(' ');

  return select;
};

const getSelectVar = (v) => {
  if (v.variable) {
    return getVar(v);
  }
  if (v.kind === '*') {
    return '*';
  }
  if (v.as) {
    return `(${getExpression(v.expression)} AS ${getVar(v.as)})`;
  }
};

const addFilter = (filter) => {
  if (filter.value.expressionType === 'builtincall' && filter.value.builtincall === 'notexists') {
    addLine(`FILTER NOT EXISTS`);
    filter.value.args.forEach(addGGP);
  } else if (filter.value.expressionType === 'builtincall' && filter.value.builtincall === 'exists') {
    addLine(`FILTER EXISTS`);
    filter.value.args.forEach(addGGP);
  } else {
    addLineWithComment(`FILTER ${getExpression(filter.value)}`, filter.location.start.offset);
  }
};

const addTriples = (triples) => {
  triples.forEach((t) => {
    if (t.graph) {
      addLineWithComment(`GRAPH ${getTripleElem(t.graph)} {`, t.graph.location.start.offset);
      increaseIndent();
      addTriples(t.triplePattern);
      decreaseIndent();
      addLine('}');
    } else if (t.triplePattern) {
      addTriples(t.triplePattern);
    } else {
      addTriplePath(t);
    }
  });
};

const addTriplePath = (triplepath) => {
  const s = getTripleElem(triplepath.subject);
  let out;
  let outPos;
  triplepath.properties.forEach((pair) => {
    const p = getTripleElem(pair[0]);
    const o = getTripleElem(pair[1]);
    if (out) {
      addLineWithComment(`${out} ;`, outPos);
      out = ' '.repeat(s.length) + ` ${p} ${o}`;
      if (pair[0].location) {
        outPos = pair[0].location.start.offset;
      } else {
        outPos = pair[0].value.location.start.offset;
      }
    } else {
      out = `${s} ${p} ${o}`;
      outPos = triplepath.subject.location.start.offset;
    }
  });
  addLineWithComment(`${out} .`, outPos);
};

const getProperties = (properties, sLen = 4) => {
  let ret = '';
  properties.forEach((pair) => {
    const p = getTripleElem(pair[0]);
    const o = getTripleElem(pair[1]);
    if (ret) {
      ret += ` ;\n`;
      ret += currentIndent + ' '.repeat(sLen) + ` ${p} ${o}`;
    } else {
      ret += ` ${p} ${o}`;
    }
  });
  return ret;
};

const addFunction = (func) => {
  const name = getUri(func.header.iriref);
  const args = func.header.args.map(getExpression).join(', ');
  addLine(`${name}(${args}) {`);
  increaseIndent();
  func.body.graphPattern.forEach(addPattern);
  decreaseIndent();
  addLine('}');
  addLine('');
};

const getAggregate = (expr) => {
  if (expr.aggregateType === 'count') {
    let distinct = expr.distinct ? 'DISTINCT ' : '';
    let expression;
    if (expr.expression === '*') {
      expression = '*'
    } else {
      expression = getExpression(expr.expression);
    }
    return `COUNT(${distinct}${expression})`;
  } else if (expr.aggregateType === 'sum') {
    return `sum(${getVar(expr.expression.value)})`;
  } else if (expr.aggregateType === 'min') {
    return `MIN(${getVar(expr.expression.value)})`;
  } else if (expr.aggregateType === 'max') {
    return `MAX(${getVar(expr.expression.value)})`;
  } else if (expr.aggregateType === 'avg') {
    return `AVG(${getExpression(expr.expression)})`;
  } else if (expr.aggregateType === 'sample') {
    return `SAMPLE(${getVar(expr.expression.value)})`;
  } else if (expr.aggregateType === 'group_concat') {
    let distinct = expr.distinct ? 'DISTINCT ' : '';
    let separator = '';
    if (expr.separator) {
      separator = `; SEPARATOR = "${expr.separator.value}"`;
    }
    return `GROUP_CONCAT(${distinct}${getExpression(expr.expression)}${separator})`;
  }
};

const getExpression = (expr) => {
  switch (expr.expressionType) {
    case 'atomic':
      return getTripleElem(expr.value);
    case 'irireforfunction':
      let iri = getUri(expr.iriref);
      if (expr.args) {
        iri += '(' + expr.args.map(getExpression).join(', ') + ')';
      }
      return getBracketted(iri, expr.bracketted);
    case 'builtincall':
      let args = '';
      if (expr.args) {
        args = expr.args.map(getTripleElem).join(', ');
      }
      const ret = expr.builtincall + '(' + args + ')';
      return getBracketted(ret, expr.bracketted);
    case 'unaryexpression':
      let ex = expr.unaryexpression + getExpression(expr.expression);
      return getBracketted(ex, expr.bracketted);
    case 'aggregate':
      return getAggregate(expr);
    case 'multiplicativeexpression':
      let multi = getExpression(expr.factor);
      expr.factors.forEach((elem) => {
        multi += ' ' + elem.operator + ' ' + getExpression(elem.expression);
      });
      return getBracketted(multi, expr.bracketted);
    case 'additiveexpression':
      let additive = getExpression(expr.op1);
      expr.ops.forEach((elem) => {
        additive += ' ' + elem.operator + ' ' + getExpression(elem.expression);
      });
      return getBracketted(additive, expr.bracketted);
    case 'relationalexpression':
      let relation = getExpression(expr.op1) + ' ' + expr.operator + ' ';
      if (Array.isArray(expr.op2)) {
        relation += '(' + expr.op2.map(getTripleElem).join(', ') + ')';
      } else {
        relation += getExpression(expr.op2);
      }
      return getBracketted(relation, expr.bracketted);
    case 'conditionaland':
      return getBracketted(expr.operands.map(getExpression).join(' && '), expr.bracketted);
    case 'conditionalor':
      return getBracketted(expr.operands.map(getExpression).join(' || '), expr.bracketted);
    case 'regex':
      let op = getExpression(expr.text);
      op += ', ' + getExpression(expr.pattern);
      if (expr.flags) {
        op += ', ' + getExpression(expr.flags);
      }
      return `regex(${op})`;
  }
};

const getBracketted = (ret, bracketted) => {
  if (bracketted) {
    return `(${ret})`;
  } else {
    return ret;
  }
};

const addInlineData = (inline) => {
  if (inline.oneVar) {
    const v = getTripleElem(inline.oneVar);
    const vals = inline.data.map(getTripleElem).join(' ');
    addLine(`VALUES ${v} { ${vals} }`);
  } else if (inline.variables) {
    const vars = inline.variables.map(getVar).join(' ');
    if (inline.variables.length === 1) {
      const vals = inline.data.map((tuple) => {
        return '(' + tuple.map(getTripleElem).join(' ') + ')';
      }).join(' ');
      addLine(`VALUES (${vars}) { ${vals} }`);
    } else {
      addLine(`VALUES (${vars}) {`);
      increaseIndent();
      inline.data.map((tuple) => {
        addLine('(' + tuple.map(getTripleElem).join(' ') + ')');
      });
      decreaseIndent();
      addLine('}');
    }
  }
};

const getTripleElem = (elem) => {
  if (elem === 'UNDEF') {
    return elem;
  }
  if (Array.isArray(elem)) {
    return elem.map((e) => getTripleElem(e)).join(', ');
  }
  if (elem.variable) {
    return getVar(elem);
  }
  if (elem.iri || elem.a) {
    return getUri(elem);
  }
  if (elem.collection) {
    const collection = elem.collection.map((c) => {
      return getTripleElem(c)
    }).join(' ');
    return `( ${collection} )`;
  }

  switch (elem.token) {
    case 'literal':
      if (elem.type === 'http://www.w3.org/2001/XMLSchema#decimal') {
        return elem.value;
      } else if (elem.type === 'http://www.w3.org/2001/XMLSchema#double') {
        return elem.value;
      } else if (elem.type === 'http://www.w3.org/2001/XMLSchema#integer') {
        return elem.value;
      } else if (elem.type === 'http://www.w3.org/2001/XMLSchema#boolean') {
        return elem.value;
      }
      let literal = elem.quote + elem.value + elem.quote;
      if (elem.type) {
        literal += `^^${getUri(elem.type)}`;
      } else if (elem.lang) {
        literal += '@' + elem.lang;
      }
      return literal;
    case 'blank':
      return elem.value || '[]';
    case 'triplesnode':
      return `[${getProperties(elem.properties)} ]`;
    case 'expression':
      return getExpression(elem);
  }

  let ret = '';
  if (elem.kind === 'inversePath') {
    ret += '^';
  }

  if (elem.iriPrefix || elem.iriLocal) {
    ret += getUri(elem);
  }
  if (elem.alternative) {
    ret += elem.alternative.map((e) => getTripleElem(e)).join('|');
  } else if (elem.sequence) {
    ret += elem.sequence.map((e) => getTripleElem(e)).join('/');
  }

  if (elem.bracketted) {
    ret = `(${ret})`;
  }
  if (elem.modifier) {
    ret += elem.modifier;
  }
  return ret;
};

const getUri = (uri) => {
  if (uri.iri) {
    return `<${uri.iri}>`;
  } else if (uri.iriPrefix && uri.iriLocal) {
    return `${uri.iriPrefix}:${uri.iriLocal}`;
  } else if (uri.iriPrefix) {
    return `${uri.iriPrefix}:`;
  } else if (uri.iriLocal) {
    return `:${uri.iriLocal}`;
  } else if (uri.a) {
    return 'a';
  }
};

const getVar = (variable) => {
  if (variable.varType === '$') {
    return '$' + variable.variable;
  } else if (variable.varType === '{{}}') {
    return '{{' + variable.variable + '}}';
  } else {
    return '?' + variable.variable;
  }
};
