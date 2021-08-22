let output;
let commentsList;
let currentIndent;
let indentUnit = '  ';

exports.format = (syntaxTree, indentDepth = 2) => {
  indentUnit = ' '.repeat(indentDepth);

  output = [];
  commentsList = syntaxTree.comments;
  currentIndent = '';

  if (syntaxTree.headers.length > 0) {
    addLine(syntaxTree.headers.join(''));
  }
  if (syntaxTree.prologue.length) {
    syntaxTree.prologue.forEach((p) => {
      if (p.token === 'base') {
        addLine(`BASE <${p.value}>`);
      } else if (p.token === 'prefix') {
        addLine(`PREFIX ${p.prefix || ''}: <${p.local}>`);
      }
    });
    addLine('');
  }

  syntaxTree.functions.forEach(addFunction);

  if (syntaxTree.body?.kind === 'select') {
    addSelect(syntaxTree.body);
  } else if (syntaxTree.body?.kind === 'construct') {
    addConstruct(syntaxTree.body);
  } else if (syntaxTree.body?.kind === 'ask') {
    addAsk(syntaxTree.body);
  } else if (syntaxTree.body?.kind === 'describe') {
    addDescribe(syntaxTree.body);
  } else if (syntaxTree.units) {
    syntaxTree.units.forEach((unit) => {
      addUnit(unit);
    });
  }
  if (syntaxTree.inlineData) {
    addInlineData(syntaxTree.inlineData);
  }

  addComments();

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

const addLine = (lineText, commentPtr = 0) => {
  // 0 means min ptr, so no comments will be added.
  addComments(commentPtr);
  output.push(currentIndent + lineText);
};

const addComments = (commentPtr = -1) => {
  // -1 means 'max' ptr, so all comments will be added.
  let commentAdded = false;
  while (commentsList.length > 0 && (commentsList[0].line < commentPtr || commentPtr == -1)) {
    const commentText = commentsList.shift().text;
    if (commentAdded || commentPtr == -1 || output[output.length - 1] === '') {
      // newline is necessary before comment
      output.push(commentText);
    } else {
      // newline is not necessary
      output[output.length - 1] += commentText;
    }
    commentAdded = true;
  }
};

const addAsk = (ask) => {
  addLine('ASK {');
  addGroupGraphPatternSub(ask.pattern);
  addLine('}');
}

const addDescribe = (describe) => {
  const elems = describe.value.map(getTripleElem).join(' ');
  addLine(`DESCRIBE ${elems}`);
  if (describe.pattern) {
    addLine('WHERE {');
    addGroupGraphPatternSub(describe.pattern);
    addLine('}');
  }
}

const addUnit = (unit) => {
  if (unit.kind === 'insertdata') {
    addLine('INSERT DATA');
    addQuads(unit.quads);
  } else if (unit.kind === 'deletedata') {
    addLine('DELETE DATA');
    addQuads(unit.quads);
  } else if (unit.kind === 'deletewhere') {
    addLine('DELETE WHERE {');
    addGroupGraphPatternSub(unit.pattern);
    addLine('}');
  } else if (unit.kind === 'modify') {
    if (unit.with) {
      addLine(`WITH ${getTripleElem(unit.with)}`);
    }
    if (unit.delete && unit.insert) {
      addLine('DELETE INSERT');
    } else if (unit.delete) {
      addLine('DELETE');
      addQuads(unit.delete.quadsContext);
    } else if (unit.insert) {
      addLine('INSERT');
      addQuads(unit.insert.quadsContext);
    }
    addLine('WHERE {');
    addGroupGraphPatternSub(unit.pattern);
    addLine('}');
  }
};

const addQuads = (quads) => {
  addLine('{');
  increaseIndent();
  quads.forEach((quad) => {
    addTriple(quad);
  });
  decreaseIndent();
  addLine('}');
};

const addSelect = (select) => {
  const proj = select.projection;
  const lastLine = proj[0].value ? proj[0].value.location.start.line : proj[0].location.start.line;

  let args = '';
  if (select.modifier) {
    args += `${select.modifier.toString()} `;
  }
  args += proj.map(getProjection).join(' ');
  addLine(`SELECT ${args}`, lastLine);

  if (select.dataset) {
    select.dataset.implicit.forEach((graph) => {
      addFrom(graph);
    });
    select.dataset.named.forEach((graph) => {
      addFromNamed(graph);
    });
  }

  addLine('WHERE {', lastLine + 1);
  addGroupGraphPatternSub(select.pattern);
  addLine('}', select.pattern.location.end.line);

  if (select.group) {
    addLine('GROUP BY ' + select.group.map(elem => getTripleElem(elem)).join(' '));
  }
  if (select.having) {
    addLine(`HAVING (${getExpression(select.having[0])})`);
  }
  if (select.order) {
    addLine('ORDER BY ' + getOrderConditions(select.order));
  }
  if (select.limit) {
    addLine(`LIMIT ${select.limit}`);
  }
  if (select.offset) {
    addLine(`OFFSET ${select.offset}`);
  }
};

const addConstruct = (body) => {
  addLine('CONSTRUCT {');
  increaseIndent();
  body.template.triplesContext.forEach((triple) => {
    addTriple(triple);
  });
  decreaseIndent();
  addLine('}');

  body.dataset.implicit.forEach((graph) => {
    addFrom(graph);
  });
  body.dataset.named.forEach((graph) => {
    addFromNamed(graph);
  });

  addLine('WHERE {');
  if (body.pattern.patterns) {
    addGroupGraphPatternSub(body.pattern);
  } else {
    increaseIndent();
    addPattern(body.pattern);
    decreaseIndent();
  }
  addLine('}');
};

const addFrom = (graph) => {
  const uri = getUri(graph);
  if (uri != null) {
    addLine('FROM ' + uri);
  }
};

const addFromNamed = (graph) => {
  const uri = getUri(graph);
  if (uri != null) {
    addLine('FROM NAMED ' + uri);
  }
};

const addGroupGraphPatternSub = (pattern) => {
  increaseIndent();
  pattern.patterns.forEach((p) => {
    if (p.token === 'filter') {
      addFilter(p)
    } else if (p.token === 'bind') {
      addBind(p)
    } else {
      addPattern(p)
    }
  });
  decreaseIndent();
};

const addBind = (bind) => {
  addLine(`BIND(${getExpression(bind.expression)} AS ${getVar(bind.as)})`);
}

const addPattern = (pattern) => {
  switch (pattern.token) {
    case 'ggps':
      addLine('{');
      addGroupGraphPatternSub(pattern);
      addLine('}');
      break;
    case 'graphgraphpattern':
      addLine(`GRAPH ${getTripleElem(pattern.graph)} {`);
      addGroupGraphPatternSub(pattern.value);
      addLine('}');
      break;
    case 'graphunionpattern':
      addLine('{');
      addGroupGraphPatternSub(pattern.value[0]);
      addLine('}');
      for (let i = 1; i < pattern.value.length; i++) {
        addLine('UNION');
        addLine('{');
        addGroupGraphPatternSub(pattern.value[i]);
        addLine('}');
      }
      break;
    case 'optionalgraphpattern':
      addLine('OPTIONAL {');
      addGroupGraphPatternSub(pattern.value);
      addLine('}');
      break;
    case 'servicegraphpattern':
      addLine(`SERVICE ${getTripleElem(pattern.value[0])}`);
      addPattern(pattern.value[1]);
      break;
    case 'minusgraphpattern':
      addLine('MINUS {');
      addGroupGraphPatternSub(pattern.value);
      addLine('}');
      break;
    case 'bgp':
      pattern.triplesContext.forEach(addTriple);
      break;
    case 'triplesblock':
      pattern.triplesContext.forEach(addTriple);
      break;
    case 'inlineData':
      addInlineData(pattern);
      break;
    case 'inlineDataFull':
      addInlineData(pattern);
      break;
    case 'expression':
      if (pattern.expressionType === 'functioncall') {
        const args = pattern.args.map(getExpression).join(', ');
        addLine(getUri(pattern.iriref) + `(${args})`);
      } else {
        debugPrint(pattern);
      }
      break;
    case 'subselect':
      addLine('{');
      increaseIndent();
      addSelect(pattern);
      decreaseIndent();
      addLine('}');
      break;
    default:
      debugPrint(pattern);
  }
};

const getOrderConditions = (conditions) => {
  let orderConditions = [];
  conditions.forEach((condition) => {
    const oc = getVar(condition.expression.value);
    if (condition.direction == 'DESC') {
      orderConditions.push(`DESC(${oc})`);
    } else {
      orderConditions.push(oc);
    }
  });

  return orderConditions.join(' ');
};

const getProjection = (projection) => {
  switch (projection.kind) {
    case '*':
      return '*';
    case 'var':
      if (projection.value.prefix === '$') {
        return '$' + projection.value.value;
      } else {
        return '?' + projection.value.value;
      }
    case 'aliased':
      return `(${getExpression(projection.expression)} AS ?${projection.alias.value})`;
    default:
      throw new Error('unknown projection.kind: ' + projection.kind);
  }
};

const getRelationalExpression = (exp) => {
  let op1 = getExpression(exp.op1);
  if (exp.op1.bracketted) {
    op1 = `(${op1})`;
  }

  let op2;
  if (Array.isArray(exp.op2)) {
    op2 = exp.op2.map(getTripleElem).join(', ');
    op2 = `(${op2})`;
  } else {
    op2 = getExpression(exp.op2);
  }

  return `${op1} ${exp.operator} ${op2}`;
}

const addFilter = (filter) => {
  if (filter.value.expressionType == 'relationalexpression') {
    addLine(`FILTER (${getRelationalExpression(filter.value)})`);
  } else if (filter.value.expressionType == 'regex') {
    let op = getExpression(filter.value.text);
    op += ', ' + getExpression(filter.value.pattern);
    if (filter.value.flags) {
      op += ', ' + getExpression(filter.value.flags);
    }
    addLine(`FILTER regex(${op})`);
  } else if (filter.value.expressionType === 'builtincall' && filter.value.builtincall === 'notexists') {
    addLine(`FILTER NOT EXISTS`);
    filter.value.args.forEach((pattern) => {
      addPattern(pattern);
    });
  } else if (filter.value.expressionType === 'builtincall' && filter.value.builtincall === 'exists') {
    addLine(`FILTER EXISTS`);
    filter.value.args.forEach((pattern) => {
      addPattern(pattern);
    });
  } else if (filter.value.expressionType === 'conditionaland') {
    let operands = filter.value.operands.map((operand) => {
      return getExpression(operand);
    }).join(' && ');
    if (filter.value.bracketted) {
      addLine(`FILTER (${operands})`);
    } else {
      addLine(`FILTER ${operands}`);
    }
  } else {
    addLine(`FILTER ${getExpression(filter.value)}`);
  }
};

const addFunction = (func) => {
  const name = getUri(func.header.iriref);
  const args = func.header.args.map(getExpression).join(', ');
  addLine(`${name}(${args}) {`);
  addGroupGraphPatternSub(func.body);
  addLine('}');
  addLine('');
};

const addTriple = (triple) => {
  const s = getTripleElem(triple.subject);
  const p = getTripleElem(triple.predicate);
  const o = getTripleElem(triple.object);
  addLine(`${s} ${p} ${o} .`, triple.object.location?.end.line);
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
      return iri;
    case 'builtincall':
      let args = '';
      if (expr.args) {
        args = expr.args.map(getTripleElem).join(', ');
      }
      const ret = expr.builtincall + '(' + args + ')';
      if (expr.bracketted) {
        return `(${ret})`;
      } else {
        return ret;
      }
    case 'unaryexpression':
      let ex = expr.unaryexpression + getExpression(expr.expression);
      if (expr.bracketted) {
        return `(${ex})`;
      } else {
        return ex;
      }
    case 'aggregate':
      if (expr.aggregateType === 'sample') {
        return `SAMPLE(?${expr.expression.value.value})`;
      } else if (expr.aggregateType === 'avg') {
        return `AVG(${getExpression(expr.expression)})`;
      } else if (expr.aggregateType === 'sum') {
        return `sum(?${expr.expression.value.value})`;
      } else if (expr.aggregateType === 'min') {
        return `MIN(?${expr.expression.value.value})`;
      } else if (expr.aggregateType === 'max') {
        return `MAX(?${expr.expression.value.value})`;
      } else if (expr.aggregateType === 'count') {
        let distinct = expr.distinct ? 'DISTINCT ' : '';
        return `COUNT(${distinct}${getExpression(expr.expression)})`;
      } else if (expr.aggregateType === 'group_concat') {
        let distinct = expr.distinct ? 'DISTINCT ' : '';
        let separator = '';
        if (expr.separator) {
          separator = `; SEPARATOR = "${expr.separator.value}"`;
        }
        return `GROUP_CONCAT(${distinct}${getExpression(expr.expression)}${separator})`;
      }
    case 'multiplicativeexpression':
      let multi = getFactor(expr.factor) + ' ' + getFactors(expr.factors);
      if (expr.bracketted) {
        return `(${multi})`;
      } else {
        return multi;
      }
    case 'additiveexpression':
      return getFactor(expr);
    case 'relationalexpression':
      return getRelationalExpression(expr);
  }
  return expr.expressionType;
};

const getFactor = (factor) => {
  let out;
  if (factor.summand) {
    out = getExpression(factor.summand) + ' ' + getFactors(factor.summands);
  } else {
    out = getExpression(factor);
  }
  if (factor.bracketted) {
    return `(${out})`;
  } else {
    return out;
  }
};

const getFactors = (factors) => {
  return factors.map((factor) => {
    return factor.operator + ' ' + getExpression(factor.expression);
  }).join(' ');
};

const addInlineData = (inline) => {
  switch (inline.token) {
    case 'inlineData':
      const v = getTripleElem(inline.var);
      const vals = inline.values.map(getTripleElem).join(' ');
      addLine(`VALUES ${v} { ${vals} }`);
      break;
    case 'inlineDataFull':
      const varlist = inline.variables.map(getVar).join(' ');
      if (inline.variables.length === 1) {
        const vals = inline.values.map((tuple) => {
          return '(' + tuple.map(getTripleElem).join(' ') + ')';
        }).join(' ');
        addLine(`VALUES (${varlist}) { ${vals} }`);
      } else {
        addLine(`VALUES (${varlist}) {`);
        increaseIndent();
        inline.values.map((tuple) => {
          addLine('(' + tuple.map(getTripleElem).join(' ') + ')');
        });
        decreaseIndent();
        addLine('}');
      }
      break;
  }
};

const getTripleElem = (elem) => {
  if (elem === 'UNDEF') {
    return elem;
  }
  switch (elem.token) {
    case 'uri':
      return getUri(elem);
    case 'var':
      return getVar(elem);
    case 'literal':
      if (elem.type === 'http://www.w3.org/2001/XMLSchema#decimal') {
        return elem.value;
      } else if (elem.type === 'http://www.w3.org/2001/XMLSchema#double') {
        return elem.value;
      } else if (elem.type === 'http://www.w3.org/2001/XMLSchema#integer') {
        return elem.value;
      } else if (elem.type?.prefix && elem.type?.suffix) {
        return `"${elem.value}"^^${elem.type.prefix}:${elem.type.suffix}`;
      } else if (elem.type) {
        return `"${elem.value}"^^<${elem.type.value}>`;
      } else if (elem.lang) {
        return `"${elem.value}"@${elem.lang}`;
      } else {
        return `"${elem.value}"`;
      }
    case 'path':
      if (elem.kind === 'alternative') {
        let path = elem.value.map((e) => getPredicate(e)).join('|');
        if (elem.bracketted) {
          path = `(${path})`;
        }
        return path;
      } else if (elem.kind === 'sequence') {
        return elem.value.map((e) => getPredicate(e)).join('/');
      } else {
        return getPredicate(elem);
      }
    case 'blank':
      return '[]';
    default:
      return getExpression(elem);
  }
};

const getPredicate = (elem) => {
  let ret = '';
  if (elem.kind === 'inversePath') {
    ret += '^';
  }
  ret += getTripleElem(elem.value);
  if (elem.modifier) {
    ret += elem.modifier;
  }
  return ret;
};

const getUri = (uri) => {
  if (uri.prefix && uri.suffix) {
    return `${uri.prefix}:${uri.suffix}`;
  } else if (uri.prefix) {
    return `${uri.prefix}:`;
  } else if (uri.suffix) {
    return `:${uri.suffix}`;
  } else if (uri.value === 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type') {
    return 'a';
  } else if (uri.value != null) {
    return `<${uri.value}>`;
  } else {
    return null;
  }
};

const getVar = (variable) => {
  if (variable.prefix === '?') {
    return '?' + variable.value;
  } else if (variable.prefix === '$') {
    return '$' + variable.value;
  } else {
    return '{{' + variable.value + '}}';
  }
};
