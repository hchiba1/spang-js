{
  let Comments = {};

  let GlobalBlankNodeCounter = 0;

  function flattenString(arr) {
    return arr.map((a) => {
      if (typeof(a) === 'string') {
        return a;
      } else {
        return a.join('');
      }
    }).join('');
  }
}

DOCUMENT = h:(HEADER_LINE*) WS* s:SPARQL WS* f:(Function*) WS*
{
  s.headers = h;
  s.comments = Object.entries(Comments).map(([loc, str]) => ({
    text: str,
    line: parseInt(loc),
  }));

  if (s.functions) {
    s.functions = s.functions.concat(f);
  } else {
    s.functions = f;
  }

  return s;
}

SPARQL = QueryUnit / UpdateUnit

// [1] QueryUnit ::= Query
QueryUnit = Query

// [2] Query ::= Prologue ( SelectQuery | ConstructQuery | DescribeQuery | AskQuery ) ValuesClause
// Function is added after Prologue
Query = p:Prologue WS* f:(Function*) WS* q:( SelectQuery / ConstructQuery / DescribeQuery / AskQuery ) v:ValuesClause
{
  return {
    token: 'query',
    prologue: p,
    body: q,
    functions: f,
    inlineData: v
  }
}

Function = h:FunctionCall WS* b:GroupGraphPattern WS*
{
  return {
    token: 'function',
    header: h,
    body: b,
    location: location(),
  }
}

// [3] UpdateUnit ::= Update
UpdateUnit = Update

// [4] Prologue ::= ( BaseDecl | PrefixDecl )*
// Prologue  ::=  BaseDecl? PrefixDecl*
Prologue = b:BaseDecl? WS* p:PrefixDecl*
{
  return {
    token: 'prologue',
    base: b,
    prefixes: p,
  }
}

// [5] BaseDecl ::= 'BASE' IRIREF
BaseDecl = WS* 'BASE'i WS* i:IRIREF
{
  return {
    token: 'base',
    value: i,
  }
}

// [6] PrefixDecl ::= 'PREFIX' PNAME_NS IRIREF
PrefixDecl = WS* 'PREFIX'i  WS* p:PNAME_NS  WS* l:IRIREF
{
  return {
    token: 'prefix',
    prefix: p,
    local: l,
  }
}

// [7] SelectQuery ::= SelectClause DatasetClause* WhereClause SolutionModifier
SelectQuery = s:SelectClause WS* gs:DatasetClause* WS* w:WhereClause WS* sm:SolutionModifier WS* BindingsClause 
{
  const dataset = { named: [], implicit: [] };
  gs.forEach((g) => {
    if (g.kind === 'default') {
      dataset.implicit.push(g.graph);
    } else {
      dataset.named.push(g.graph);
    }
  });

  if (dataset.named.length === 0 && dataset.implicit.length === 0) {
    dataset.implicit.push({
      token:'uri',
      location: null,
      prefix: null,
      suffix: null,
    });
  }

  let query = {
    token: 'executableunit',
    kind: 'select',
    dataset: dataset,
    projection: s.vars,
    modifier: s.modifier,
    pattern: w,
    location: location(),
  }

  if (sm != null) {
    if (sm.limit != null) {
      query.limit = sm.limit;
    }
    if (sm.offset != null) {
      query.offset = sm.offset;
    }
    if (sm.group != null) {
      query.group = sm.group;
    }
    if (sm.order != null && sm.order != "") {
      query.order = sm.order;
    }
  }

  return query;
}

// [8] SubSelect ::= SelectClause WhereClause SolutionModifier ValuesClause
// add ValuesClause
SubSelect = s:SelectClause w:WhereClause sm:SolutionModifier
{
  let query = {
    token: 'subselect',
    kind: 'select',
    projection: s.vars,
    modifier: s.modifier,
    pattern: w,
  };

  if (sm != null) {
    if (sm.limit != null) {
      query.limit = sm.limit;
    }
    if (sm.offset != null) {
      query.offset = sm.offset;
    }
    if (sm.group != null) {
      query.group = sm.group;
    }
    if (sm.order != null && sm.order != "") {
      query.order = sm.order;
    }
  }
  
  return query;
}

// [9] SelectClause ::= 'SELECT' ( 'DISTINCT' | 'REDUCED' )? ( ( Var | ( '(' Expression 'AS' Var ')' ) )+ | '*' )
SelectClause = WS* 'SELECT'i WS* mod:( 'DISTINCT'i / 'REDUCED'i )? WS*
  proj:( ( ( WS* Var WS* ) / ( WS* '(' WS* Expression WS* 'AS'i WS* Var WS* ')' WS* ) )+ / ( WS* '*' WS* )  ) 
{
  let s = {};

  if (mod) {
    s.modifier = mod.toUpperCase();
  }

  if (proj.length === 3 && proj[1] === "*") {
    s.vars = [{
      token: 'variable',
      kind: '*',
      location: location(),
    }];
  } else {
    s.vars = proj.map((elem) => {
      if (elem.length === 3) {
        return {
          token: 'variable',
          kind: 'var',
          value: elem[1],
        };
      } else {
        return {
          token: 'variable',
          kind: 'aliased',
          expression: elem[3],
          alias: elem[7],
          location: location(),
        };
      }
    });
  }

  return s;
}

// [10] ConstructQuery ::= 'CONSTRUCT' ( ConstructTemplate DatasetClause* WhereClause SolutionModifier | DatasetClause* 'WHERE' '{' TriplesTemplate? '}' SolutionModifier )
ConstructQuery = WS* 'CONSTRUCT'i WS* t:ConstructTemplate WS* gs:DatasetClause* WS* w:WhereClause WS* sm:SolutionModifier
{
  const dataset = { named:[], implicit:[] };
  gs.forEach((g) => {
    if (g.kind === 'default') {
      dataset.implicit.push(g.graph);
    } else {
      dataset.named.push(g.graph);
    }
  });

  if (dataset.named.length === 0 && dataset.implicit.length === 0) {
    dataset.implicit.push({
      token:'uri',
      prefix:null,
      suffix:null,
    });
  }
  
  let query = {
    kind: 'construct',
    token: 'executableunit',
    dataset: dataset,
    template: t,
    pattern: w,
    location: location(),
  };

  if (sm != null) {
    if (sm.limit != null) {
      query.limit = sm.limit;
    }
    if (sm.offset != null) {
      query.offset = sm.offset;
    }
    if (sm.order != null && sm.order != "") {
      query.order = sm.order;
    }
  }

  return query
}
/ WS* 'CONSTRUCT'i WS* gs:DatasetClause* WS* 'WHERE'i WS* '{' WS* t:TriplesTemplate? WS* '}' WS* sm:SolutionModifier
{
  let dataset = { named: [], implicit: [] };
  gs.forEach((g) => {
    if (g.kind === 'default') {
      dataset.implicit.push(g.graph);
    } else {
      dataset.named.push(g.graph)
    }
  });

  if (dataset.named.length === 0 && dataset.implicit.length === 0) {
    dataset.implicit.push({
      token:'uri',
      prefix:null,
      suffix:null,
    });
  }
  
  let query = {
    kind: 'construct',
    token: 'executableunit',
    dataset: dataset,
    template: t,
    pattern: {
      token: "basicgraphpattern",
      triplesContext: t.triplesContext
    },
    location: location(),
  };
  
  if (sm != null) {
    if (sm.limit != null) {
      query.limit = sm.limit;
    }
    if (sm.offset != null) {
      query.offset = sm.offset;
    }
    if (sm.order != null && sm.order != "") {
      query.order = sm.order;
    }
  }

  return query
}

// [11] DescribeQuery ::= 'DESCRIBE' ( VarOrIri+ | '*' ) DatasetClause* WhereClause? SolutionModifier
DescribeQuery = 'DESCRIBE'i ( VarOrIri+ / '*' ) DatasetClause* WhereClause? SolutionModifier

// [12] AskQuery ::= 'ASK' DatasetClause* WhereClause SolutionModifier
// add SolutionModifier
AskQuery = WS* 'ASK'i WS* gs:DatasetClause* WS* w:WhereClause 
{
  const dataset = { named: [], implicit: [] };
  gs.forEach((g) => {
    if(g.kind === 'implicit') {
      dataset.implicit.push(g.graph);
    } else {
      dataset.named.push(g.graph);
    }
  });

  if (dataset.named.length === 0 && dataset.implicit.length === 0) {
    dataset.implicit.push({
      token:'uri',
      prefix:null,
      suffix:null,
    });
  }

  return {
    kind: 'ask',
    token: 'executableunit',
    dataset: dataset,
    pattern: w,
    location: location(),
  }
}

// [13] DatasetClause ::= 'FROM' ( DefaultGraphClause | NamedGraphClause )
DatasetClause = 'FROM'i WS* gs:( DefaultGraphClause / NamedGraphClause ) WS*
{
  return gs;
}

// [14] DefaultGraphClause ::= SourceSelector
DefaultGraphClause = WS* s:SourceSelector
{
  return {
    kind: 'default',
    token: 'graphClause',
    graph: s,
    location: location(),
  }
}

// [15] NamedGraphClause ::= 'NAMED' SourceSelector
NamedGraphClause = 'NAMED'i WS* s:SourceSelector
{
  return {
    token: 'graphCluase',
    kind: 'named',
    graph: s,
    location: location(),
  };
}

// [16] SourceSelector ::= IRIref
SourceSelector = IRIref

// [17] WhereClause ::= 'WHERE'? GroupGraphPattern
WhereClause = ('WHERE'i)? WS* g:GroupGraphPattern WS*
{
  return g;
}

// [18] SolutionModifier ::= GroupClause? HavingClause? OrderClause? LimitOffsetClauses?
SolutionModifier = gc:GroupClause? HavingClause? oc:OrderClause? lo:LimitOffsetClauses? 
{
  let sm = {};

  if (gc != null) {
    sm.group = gc;
  }

  sm.order = oc;

  if (lo != null) {
    if (lo.limit != null) {
      sm.limit = lo.limit;
    }
    if (lo.offset != null) {
      sm.offset = lo.offset;
    }
  }

  return sm
}
                             
// [19] GroupClause ::= 'GROUP' 'BY' GroupCondition+
GroupClause = 'GROUP'i WS* 'BY'i WS* conds:GroupCondition+
{
  return conds;
}

// [20] GroupCondition ::= BuiltInCall | FunctionCall | '(' Expression ( 'AS' Var )? ')' | Var
GroupCondition = WS* b:BuiltInCall WS* 
{
  return b;
}
/ WS* f:FunctionCall WS*
{
  return f;
}
/ WS* '(' WS* e:Expression WS*  alias:( 'AS'i WS* Var )?  WS* ')' WS*
{
  if (alias.length != 0) {
    return {
      token: 'aliased_expression',
      expression: e,
      alias: alias[2],
      location: location(),
    };
  } else {
    return e;
  }
}
/ WS* v:Var WS*
{
  return v;
}

// [21] HavingClause ::= 'HAVING' HavingCondition+
HavingClause = 'HAVING' HavingCondition+

// [22] HavingCondition ::= Constraint
HavingCondition = Constraint

// [23] OrderClause ::= 'ORDER' 'BY' OrderCondition+
OrderClause = 'ORDER'i WS* 'BY'i WS* os:OrderCondition+ WS*
{
  return os;
}

// [24] OrderCondition ::= ( ( 'ASC' | 'DESC' ) BrackettedExpression ) | ( Constraint | Var )
OrderCondition = direction:( 'ASC'i / 'DESC'i ) WS* e:BrackettedExpression WS*
{
  return {
    direction: direction.toUpperCase(),
    expression: e
  };
}
/ e:( Constraint / Var ) WS*
{
  if (e.token === 'var') {
    return {
      direction: 'ASC',
      expression: {
        value: e,
        token:'expression',
        expressionType:'atomic',
        primaryexpression: 'var',
        location: location(),
      }
    };
  } else {
    return {
      direction: 'ASC',
      expression: e,
    };
  }
}

// [25] LimitOffsetClauses ::= LimitClause OffsetClause? | OffsetClause LimitClause?
LimitOffsetClauses = cls:( LimitClause OffsetClause? / OffsetClause LimitClause? )
{
  let acum = {};

  cls.forEach((cl) => {
    if (cl != null && cl.limit != null) {
      acum.limit = cl.limit;
    } else if (cl != null && cl.offset != null){
      acum.offset = cl.offset;
    }
  });
  
  return acum;
}

// [26] LimitClause ::= 'LIMIT' INTEGER
LimitClause = 'LIMIT'i WS* i:INTEGER WS*
{
  return {
    limit: parseInt(i.value)
  };
}

// [27] OffsetClause ::= 'OFFSET' INTEGER
OffsetClause = 'OFFSET'i WS* i:INTEGER WS*
{
  return {
    offset: parseInt(i.value)
  };
}

// BindingsClause ::= ( 'BINDINGS' Var* '{' ( '(' BindingValue+ ')' | NIL )* '}' )?
BindingsClause = ( 'BINDINGS' Var* '{' ( '(' BindingValue+ ')' / NIL )* '}' )?

// BindingValue ::= IRIref | RDFLiteral | NumericLiteral | BooleanLiteral | 'UNDEF'
BindingValue = IRIref / RDFLiteral / NumericLiteral / BooleanLiteral / 'UNDEF'

// [28] ValuesClause ::= ( 'VALUES' DataBlock )?
ValuesClause = b:( 'VALUES'i DataBlock )?
{
  if (b != null) {
    return b[1];
  } else {
    return null;
  }
}

// [29] Update ::= Prologue ( Update1 ( ';' Update )? )?
// Update ::= Prologue Update1 ( ';' Update? )?
Update = p:Prologue WS* u:Update1 us:( WS* ';' WS* Update? )?
{
  let query = {
    token: 'update',
    prologue: p,
  };
  
  let units = [u];
  if (us != null && us.length != null && us[3] != null && us[3].units != null) {
    units = units.concat(us[3].units);
  }
  query.units = units;

  return query;
}

// [30] Update1 ::= Load | Clear | Drop | Add | Move | Copy | Create | InsertData | DeleteData | DeleteWhere | Modify
// Update1 = Load / Clear / Drop / Add / Move / Copy / Create / InsertData / DeleteData / DeleteWhere / Modify
Update1 = Load / Clear / Drop / Create / InsertData / DeleteData / DeleteWhere / Modify

// [31] Load ::= 'LOAD' 'SILENT'? IRIref ( 'INTO' GraphRef )?
// Load ::= 'LOAD' IRIref ( 'INTO' GraphRef )?
Load = 'LOAD'i WS* sg:IRIref WS* dg:( 'INTO'i WS* GraphRef)?
{
  let query = {
    kind: 'load',
    token: 'executableunit',
    sourceGraph: sg,
  };
  if (dg != null) {
    query.destinyGraph = dg[2];
  }

  return query;
}

// [32] Clear ::= 'CLEAR' 'SILENT'? GraphRefAll
Clear = 'CLEAR'i WS* 'SILENT'i? WS* ref:GraphRefAll
{
  return {
    token: 'executableunit',
    kind: 'clear',
    destinyGraph: ref,
  }
}

// [33] Drop ::= 'DROP' 'SILENT'? GraphRefAll
Drop = 'DROP'i  WS* 'SILENT'i? WS* ref:GraphRefAll
{
  return {
    token: 'executableunit',
    kind: 'drop',
    destinyGraph: ref,
  }
}

// [34] Create ::= 'CREATE' 'SILENT'? GraphRef
Create = 'CREATE'i WS* 'SILENT'i? WS* ref:GraphRef
{
  return {
    token: 'executableunit',
    kind: 'create',
    destinyGraph: ref,
  }
}

// [35] Add ::= 'ADD' 'SILENT'? GraphOrDefault 'TO' GraphOrDefault
// [36] Move ::= 'MOVE' 'SILENT'? GraphOrDefault 'TO' GraphOrDefault
// [37] Copy ::= 'COPY' 'SILENT'? GraphOrDefault 'TO' GraphOrDefault

// [38] InsertData ::= 'INSERT DATA' QuadData
InsertData = 'INSERT'i WS* 'DATA'i WS* qs:QuadData
{
  return {
    token: 'executableunit',
    kind: 'insertdata',
    quads: qs,
  }
}

// [39] DeleteData ::= 'DELETE DATA' QuadData
DeleteData = 'DELETE'i WS* 'DATA'i qs:QuadData
{
  return {
    token: 'executableunit',
    kind: 'deletedata',
    quads: qs,
  }
}

// [40] DeleteWhere ::= 'DELETE WHERE' QuadPattern
DeleteWhere = 'DELETE'i WS* 'WHERE'i WS* p:GroupGraphPattern
{
  let patternsCollection = p.patterns[0];
  if (patternsCollection.triplesContext == null && patternsCollection.patterns != null) {
    patternsCollection = patternsCollection.patterns[0].triplesContext;
  } else {
    patternsCollection = patternsCollection.triplesContext;
  }

  let quads = [];
  for (let i = 0; i < patternsCollection.length; i++) {
    quads.push({
      subject: patternsCollection[i].subject,
      predicate: patternsCollection[i].predicate,
      object: patternsCollection[i].object,
      graph: patternsCollection[i].graph,
    });
  }

  return {
    kind: 'modify',
    pattern: p,
    delete: quads,
    with: null,
    using: null,
  };
}

// [41] Modify ::= ( 'WITH' IRIref )? ( DeleteClause InsertClause? | InsertClause ) UsingClause* 'WHERE' GroupGraphPattern
Modify = wg:('WITH'i WS* IRIref)? WS* dic:( DeleteClause WS* InsertClause? / InsertClause ) WS* uc:UsingClause* WS* 'WHERE'i WS* p:GroupGraphPattern WS*
{
  var query = {};
  query.kind = 'modify';
  
  if(wg != "" && wg != null) {
    query.with = wg[2];
  } else {
    query.with = null;
  }
  
  
  if(dic.length === 3 && (dic[2] === ''|| dic[2] == null)) {
    query.delete = dic[0];
    query.insert = null;
  } else if(dic.length === 3 && dic[0].length != null && dic[1].length != null && dic[2].length != null) {
    query.delete = dic[0];
    query.insert = dic[2];
  } else  {
    query.insert = dic;
    query.delete = null;
  }
  
  if(uc != '') {
    query.using = uc;
  }
  
  query.pattern = p;
  
  return query;
}

// [42] DeleteClause ::= 'DELETE' QuadPattern
DeleteClause = 'DELETE'i q:QuadPattern
{
  return q;
}

// [43] InsertClause ::= 'INSERT' QuadPattern
InsertClause = 'INSERT'i q:QuadPattern
{
  return q;
}

// [44] UsingClause ::= 'USING' ( IRIref | 'NAMED' IRIref )
UsingClause = WS* 'USING'i WS* g:( IRIref / 'NAMED'i WS* IRIref )
{
  if (g.length != null) {
    return { kind: 'named', uri: g[2] };
  } else {
    return { kind: 'default', uri: g };
  }
}

// [45] GraphOrDefault ::= 'DEFAULT' | 'GRAPH'? iri

// [46] GraphRef ::= 'GRAPH' IRIref
GraphRef = 'GRAPH'i WS* i:IRIref
{
  return i;
}

// [47] GraphRefAll ::= GraphRef | 'DEFAULT' | 'NAMED' | 'ALL'
GraphRefAll = g:GraphRef
{
  return g;
}
/ 'DEFAULT'i
{
  return 'default';
}
/ 'NAMED'i
{
  return 'named';
}
/ 'ALL'i
{
  return 'all';
}

// [48] QuadPattern ::= '{' Quads '}'
QuadPattern = WS* '{' WS* qs:Quads WS* '}' WS*
{
  return qs.quadsContext;
}

// [49] QuadData ::= '{' Quads '}'
QuadData = WS* '{' WS* qs:Quads WS* '}' WS*
{
  return qs.quadsContext;
}

// [50] Quads ::= TriplesTemplate? ( QuadsNotTriples '.'? TriplesTemplate? )*
Quads = ts:TriplesTemplate? qs:( QuadsNotTriples '.'? TriplesTemplate? )*
{
  let quads = [];
  if (ts != null && ts.triplesContext != null) {
    for (var i=0; i<ts.triplesContext.length; i++) {
      let triple = ts.triplesContext[i]
      triple.graph = null;
      quads.push(triple)
    }
  }

  if (qs && qs.length>0 && qs[0].length > 0) {
    quads = quads.concat(qs[0][0].quadsContext);
    
    if (qs[0][2] != null && qs[0][2].triplesContext != null) {
      for (let i = 0; i < qs[0][2].triplesContext.length; i++) {
        let triple = qs[0][2].triplesContext[i]
        triple.graph = null;
        quads.push(triple)
      }
    }
  }
  
  return {
    token:'quads',
    quadsContext: quads,
    location: location(),
  }
}

// [51] QuadsNotTriples ::= 'GRAPH' VarOrIri '{' TriplesTemplate? '}'
QuadsNotTriples = WS* 'GRAPH'i WS* g:VarOrIri WS* '{' WS* ts:TriplesTemplate? WS* '}' WS*
{
  let quads = [];
  if (ts!=null) {
    for (let i = 0; i < ts.triplesContext.length; i++) {
      let triple = ts.triplesContext[i];
      triple.graph = g;
      quads.push(triple)
    }
  }
  
  return {
    token:'quadsnottriples',
    quadsContext: quads,
    location: location(),
  }
}

// [52] TriplesTemplate ::= TriplesSameSubject ( '.' TriplesTemplate? )?
TriplesTemplate = b:TriplesSameSubject bs:(WS* '.' WS* TriplesTemplate? )?
{
  let triples = b.triplesContext;
  if (bs != null && typeof(bs) === 'object') {
    if (bs.length != null) {
      if (bs[3] != null && bs[3].triplesContext!=null) {
        triples = triples.concat(bs[3].triplesContext);
      }
    }
  }
  
  return {
    token:'triplestemplate',
    triplesContext: triples,
    location: location(),
  };
}

// [53] GroupGraphPattern ::= '{' ( SubSelect | GroupGraphPatternSub ) '}'
GroupGraphPattern = '{' WS* p:SubSelect  WS* '}'
{
  return p;
}
/ '{' WS* p:GroupGraphPatternSub WS* '}' 
{
  return p;
}

// [54] GroupGraphPatternSub ::= TriplesBlock? ( GraphPatternNotTriples '.'? TriplesBlock? )*
GroupGraphPatternSub = tb:TriplesBlock? WS* tbs:( GraphPatternNotTriples WS* '.'? WS* TriplesBlock? )*
{
  let blocks = [];
  if (tb != null && tb != []) {
    blocks.push(tb);
  }
  for (let i = 0; i < tbs.length; i++) {
    for (let j = 0; j < tbs[i].length; j++) {
      if (tbs[i][j] != null && tbs[i][j].token != null) {
        blocks.push(tbs[i][j]);
      }
    }
  }

  let filters = [];
  let binds = [];
  let patterns = [];
  let tmpPatterns = [];
  blocks.forEach((block) => {
    if (block.token === 'filter') {
      filters.push(block);
    } else if (block.token === 'bind') {
      binds.push(block);
    } else if (block.token === 'triplespattern') {
      tmpPatterns.push(block);
    } else {
      if (tmpPatterns.length != 0 || filters.length != 0) {
        const tmpContext = tmpPatterns.map(pattern => pattern.triplesContext).flat();
        if (tmpContext.length > 0) {
          patterns.push({ token: 'basicgraphpattern', triplesContext: tmpContext, location: location() });
        }
        tmpPatterns = [];
      }
      patterns.push(block);
    }
  });
  if (tmpPatterns.length != 0 || filters.length != 0) {
    const tmpContext = tmpPatterns.map(pattern => pattern.triplesContext).flat();
    if (tmpContext.length > 0) {
      patterns.push({ token: 'basicgraphpattern', triplesContext: tmpContext, location: location() });
    }
  }

//      if(patterns.length == 1) {
//          patterns[0].filters = filters;
//          return patterns[0];
//      } else  {
  return {
    token: 'groupgraphpattern',
    filters: filters,
    binds: binds,
    patterns: patterns,
    location: location(),
  }
//      }
}

// [55] TriplesBlock ::= TriplesSameSubjectPath ( '.' TriplesBlock? )?
TriplesBlock = b:TriplesSameSubjectPath bs:(WS*  '.' TriplesBlock? )?
{
  let triples = b.triplesContext;
  if (bs != null && typeof(bs) === 'object' &&
      bs.length != null && bs[2] != null && bs[2].triplesContext != null) {
    triples = triples.concat(bs[2].triplesContext);
  }
  
  return {
    token:'triplespattern',
    triplesContext: triples,
    location: location(),
  }
}

// [56] GraphPatternNotTriples ::= GroupOrUnionGraphPattern | OptionalGraphPattern | MinusGraphPattern | GraphGraphPattern | ServiceGraphPattern | Filter | Bind | InlineData
GraphPatternNotTriples = GroupOrUnionGraphPattern / OptionalGraphPattern / MinusGraphPattern / GraphGraphPattern / ServiceGraphPattern / Filter / Bind / InlineData / FunctionCall

// [57] OptionalGraphPattern ::= 'OPTIONAL' GroupGraphPattern
OptionalGraphPattern = WS* 'OPTIONAL'i WS* v:GroupGraphPattern
{
  return {
    token: 'optionalgraphpattern',
    value: v,
    location: location(),
  }
}

// [58] GraphGraphPattern ::= 'GRAPH' VarOrIri GroupGraphPattern
GraphGraphPattern = WS* 'GRAPH'i WS* g:VarOrIri WS* gg:GroupGraphPattern
{
  for (let i = 0; i < gg.patterns.length; i++) {
    for (let j = 0; j < gg.patterns[i].triplesContext.length; j++) {
      gg.patterns[i].triplesContext[j].graph = g;
    }
  }

  return gg;
}

// [59] ServiceGraphPattern ::= 'SERVICE' 'SILENT'? VarOrIri GroupGraphPattern
// add SILENT
ServiceGraphPattern = 'SERVICE' v:VarOrIri ggp:GroupGraphPattern
{
  return {
    token: 'servicegraphpattern',
    value: [v, ggp],
    location: location(),
  }
}

// [60] Bind ::= 'BIND' '(' Expression 'AS' Var ')'
Bind = WS* 'BIND'i WS* '(' WS* ex:Expression WS* 'AS'i WS* v:Var WS* ')'
{
  return {
    token: 'bind',
    expression: ex,
    as: v,
    location: location(),
  };
}

// [61] InlineData ::= 'VALUES' DataBlock
InlineData = WS* 'VALUES'i WS* d:DataBlock
{
  return d;
}

// [62] DataBlock ::= InlineDataOneVar | InlineDataFull
DataBlock = InlineDataOneVar / InlineDataFull

// [63] InlineDataOneVar ::= Var '{' DataBlockValue* '}'
InlineDataOneVar = WS* v:Var WS* '{' WS* d:DataBlockValue* '}'
{
  return {
    token: 'inlineData',
    // values: [{
    //   'var': v,
    //   'value': d
    // }]
    var: v,
    values: d,
    location: location(),
  };
}

// [64] InlineDataFull ::= ( NIL | '(' Var* ')' ) '{' ( '(' DataBlockValue* ')' | NIL )* '}'
// for simplicity, ignore NIL, and use DataBlockTuple instead of '(' DataBlockValue* ')'
InlineDataFull = WS*  '(' WS* vars:(Var*) WS* ')' WS* '{' WS* vals:( DataBlockTuple)* WS* '}'
{
  return {
    token: 'inlineDataFull',
    variables: vars,
    // values: vars.map((v, i) => { return  { 'var': v, 'value': vals[i] }; })
    values: vals,
    location: location(),
  };
}

// for simplicity, DataBlockTuple is used
DataBlockTuple = '(' WS* val:(DataBlockValue*) WS* ')' WS*
{
  return val;
}

// [65] DataBlockValue ::= iri | RDFLiteral | NumericLiteral | BooleanLiteral | 'UNDEF'
DataBlockValue = WS* v:(IRIref / RDFLiteral / NumericLiteral / BooleanLiteral / 'UNDEF') WS*
{
  return v;
}

// [66] MinusGraphPattern ::= 'MINUS' GroupGraphPattern
MinusGraphPattern = 'MINUS'i WS* ggp:GroupGraphPattern
{
  return {
    token: 'minusgraphpattern',
    value: ggp,
    location: location(),
  }
}

// [67] GroupOrUnionGraphPattern ::= GroupGraphPattern ( 'UNION' GroupGraphPattern )*
GroupOrUnionGraphPattern = a:GroupGraphPattern b:( WS* 'UNION'i WS* GroupGraphPattern )*
{
  if (b.length === 0) {
    return a;
  }

  let lastToken = {
    token: 'graphunionpattern',
    location: location(),
    value: [a],
  };

  for (let i = 0; i < b.length; i++) {
    lastToken.value.push(b[i][3]);
  }

  return lastToken;
}

// [68] Filter ::= 'FILTER' Constraint
Filter = WS* 'FILTER'i WS* c:Constraint
{
  return {
    token: 'filter',
    value: c,
    location: location(),
  }
}

// [69] Constraint ::= BrackettedExpression | BuiltInCall | FunctionCall
Constraint = BrackettedExpression / BuiltInCall / FunctionCall

// [70] FunctionCall ::= IRIref ArgList
FunctionCall = i:IRIref WS* args:ArgList
{
  return {
    token: "expression",
    expressionType: 'functioncall',
    iriref: i,
    args: args.value,
    location: location(),
  }
}

// [71] ArgList ::= NIL | '(' 'DISTINCT'? Expression ( ',' Expression )* ')'
ArgList = NIL
{
  return {
    token: 'args',
    value: [],
  }
}
/ '(' WS* d:'DISTINCT'i? WS* e:Expression WS* es:( ',' WS* Expression)* ')'
{
  let cleanEx = [];
  for (let i = 0; i < es.length; i++) {
    cleanEx.push(es[i][2]);
  }

  let args = {
    token: 'args',
    value: [e].concat(cleanEx),
  };
  if (d != null && d.toUpperCase() === "DISTINCT") {
    args.distinct = true;
  } else {
    args.distinct = false;
  }
  return args;
}

// [72] ExpressionList ::= NIL | '(' Expression ( ',' Expression )* ')'
ExpressionList = NIL
{
  return {
    token: 'args',
    value: [],
  }
}
/ '(' WS* e:(IRIref / Expression) WS* es:( ',' WS* (IRIref / Expression))* ')'
{
  let cleanEx = [];
  for (let i = 0; i < es.length; i++) {
    cleanEx.push(es[i][2]);
  }

  return {
    token: 'args',
    value: [e].concat(cleanEx),
  }
}

// [73] ConstructTemplate ::= '{' ConstructTriples? '}'
ConstructTemplate = '{' WS* ts:ConstructTriples? WS* '}'
{
  return ts;
}

// [74] ConstructTriples ::= TriplesSameSubject ( '.' ConstructTriples? )?
ConstructTriples = b:TriplesSameSubject bs:( WS* '.' WS* ConstructTriples? )?
{
  let triples = b.triplesContext;
  if (bs != null && typeof(bs) === 'object') {
    if (bs.length != null) {
      if (bs[3] != null && bs[3].triplesContext != null) {
        triples = triples.concat(bs[3].triplesContext);
      }
    }
  }
  
  return {
    token:'triplestemplate',
    triplesContext: triples,
    location: location(),
  }
}

// [75] TriplesSameSubject ::= VarOrTerm PropertyListNotEmpty | TriplesNode PropertyList
TriplesSameSubject = WS* s:VarOrTerm WS* pairs:PropertyListNotEmpty
{
  let triplesContext = pairs.triplesContext;
  if (pairs.pairs) {
    for (let i=0; i < pairs.pairs.length; i++) {
      let pair = pairs.pairs[i];
      if (pair[1].length != null) {
        pair[1] = pair[1][0]
      }
      if (s.token && s.token === 'triplesnodecollection') {
        triplesContext.push({ subject: s.chainSubject[0], predicate: pair[0], object: pair[1] });
        triplesContext = triplesContext.concat(s.triplesContext);
      } else {
        triplesContext.push({ subject: s, predicate: pair[0], object: pair[1] });
      }
    }
  }
  
  return {
    token: 'triplessamesubject',
    chainSubject: s,
    triplesContext: triplesContext,
  }
}
/ WS* tn:TriplesNode WS* pairs:PropertyList
{
  var triplesContext = tn.triplesContext;
  var subject = tn.chainSubject;
  
  if(pairs.pairs) {
    for(var i=0; i< pairs.pairs.length; i++) {
      var pair = pairs.pairs[i];
      if(pair[1].length != null)
        pair[1] = pair[1][0]
      
      if(tn.token === "triplesnodecollection") {
        for(var j=0; j<subject.length; j++) {
          var subj = subject[j];
          if(subj.triplesContext != null) {
            var triple = {subject: subj.chainSubject, predicate: pair[0], object: pair[1]}
            triplesContext.concat(subj.triplesContext);
          } else {
            var triple = {subject: subject[j], predicate: pair[0], object: pair[1]}
            triplesContext.push(triple);
          }
        }
      } else {
        var triple = {subject: subject, predicate: pair[0], object: pair[1]}
        triplesContext.push(triple);
      }
    }
  }
  
  return {
    token: "triplessamesubject",
    triplesContext: triplesContext,
    chainSubject: subject,
  }
}

// [76] PropertyList ::= PropertyListNotEmpty?
PropertyList = PropertyListNotEmpty?

// [77] PropertyListNotEmpty ::= Verb ObjectList ( ';' ( Verb ObjectList )? )*
PropertyListNotEmpty = v:Verb WS* ol:ObjectList rest:( WS* ';' WS* ( Verb WS* ObjectList )? )*
{
  let tokenParsed = {};
  tokenParsed.token = 'propertylist';
  var triplesContext = [];
  var pairs = [];
  for (let i = 0; i < ol.length; i++) {
    if (ol[i].triplesContext != null) {
      triplesContext = triplesContext.concat(ol[i].triplesContext);
      if (ol[i].token === 'triplesnodecollection' && ol[i].chainSubject.length != null) {
        pairs.push([v, ol[i].chainSubject[0]]);
      } else {
        pairs.push([v, ol[i].chainSubject]);
      }
    } else {
      pairs.push([v, ol[i]])
    }
  }
  
  for (let i = 0; i < rest.length; i++) {
    var tok = rest[i][3];
    var newVerb  = tok[0];
    var newObjsList = tok[2] || [];
    for (let j = 0; j < newObjsList.length; j++) {
      if (newObjsList[j].triplesContext != null) {
        triplesContext = triplesContext.concat(newObjsList[j].triplesContext);
        pairs.push([newVerb, newObjsList[j].chainSubject]);
      } else {
        pairs.push([newVerb, newObjsList[j]])
      }
    }
  }
  
  tokenParsed.pairs = pairs;
  tokenParsed.triplesContext = triplesContext;
  
  return tokenParsed;
}

// [78] Verb ::= VarOrIri | 'a'
Verb = VarOrIri
/ 'a'
{
  return {
    token: 'uri',
    prefix: null,
    suffix: null,
    value: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
    location: location(),
  }
}

// [79] ObjectList ::= Object ( ',' Object )*
ObjectList = obj:Object WS* objs:( ',' WS* Object )*
{
  var toReturn = [];
  
  toReturn.push(obj);
  
  for(var i=0; i<objs.length; i++) {
    for(var j=0; j<objs[i].length; j++) {
      if(typeof(objs[i][j])=="object" && objs[i][j].token != null) {
        toReturn.push(objs[i][j]);
      }
    }
  }
  
  return toReturn;
}

// [80] Object ::= GraphNode
Object = GraphNode

// [81] TriplesSameSubjectPath ::= VarOrTerm PropertyListPathNotEmpty | TriplesNodePath PropertyListPath
// support for property paths must be added
TriplesSameSubjectPath = WS* s:VarOrTerm WS* list:PropertyListPathNotEmpty
{
  let triplesContext = list.triplesContext;

  list.pairs.forEach((pair) => {
    if (pair[1].length != null) {
      pair[1] = pair[1][0];
    }
    const triple = { subject: s, predicate: pair[0], object: pair[1] };
    if (triple.predicate.token === 'path' && triple.predicate.kind === 'element') {
      triple.predicate = triple.predicate.value;
    }
    if (s.token && s.token === 'triplesnodecollection') {
      triple.subject = s.chainSubject[0];
      triplesContext.push(triple);
      triplesContext = triplesContext.concat(s.triplesContext);
    } else {
      triplesContext.push(triple);
    }
  });

  return {
    token: 'triplessamesubject',
    chainSubject: s,
    triplesContext: triplesContext,
  }
}
/ WS* tn:TriplesNodePath WS* pairs:PropertyListPath
{
  var triplesContext = tn.triplesContext;
  var subject = tn.chainSubject;

  if(pairs != null && pairs.pairs != null) {
    for(var i=0; i< pairs.pairs.length; i++) {
      var pair = pairs.pairs[i];
      if(pair[1].length != null)
        pair[1] = pair[1][0]

      if(tn.token === "triplesnodecollection") {
        for(var j=0; j<subject.length; j++) {
          var subj = subject[j];
          if(subj.triplesContext != null) {
            var triple = {subject: subj.chainSubject, predicate: pair[0], object: pair[1]}
            triplesContext.concat(subj.triplesContext);
          } else {
            var triple = {subject: subject[j], predicate: pair[0], object: pair[1]}
            triplesContext.push(triple);
          }
        }
      } else {
        var triple = {subject: subject, predicate: pair[0], object: pair[1]}
        triplesContext.push(triple);
      }
    }
  }

  var tokenParsed = {};
  tokenParsed.token = "triplessamesubject";
  tokenParsed.triplesContext = triplesContext;
  tokenParsed.chainSubject = subject;

  return tokenParsed;
}

// [82] PropertyListPath ::= PropertyListPathNotEmpty?
PropertyListPath = PropertyListPathNotEmpty?

// [83] PropertyListPathNotEmpty ::= ( VerbPath | VerbSimple ) ObjectListPath ( ';' ( ( VerbPath | VerbSimple ) ObjectList )? )*
PropertyListPathNotEmpty = v:( VerbPath / VerbSimple ) WS* ol:ObjectListPath rest:( WS* ';' WS* ( ( VerbPath / VerbSimple ) WS* ObjectList )? )*
{
  var tokenParsed = {};
  tokenParsed.token = 'propertylist';
  var triplesContext = [];
  var pairs = [];
  var test = [];
  
  for (let i=0; i<ol.length; i++) {
    
    if (ol[i].triplesContext != null) {
      triplesContext = triplesContext.concat(ol[i].triplesContext);
      if (ol[i].token==='triplesnodecollection' && ol[i].chainSubject.length != null) {
        pairs.push([v, ol[i].chainSubject[0]]);
      } else {
        pairs.push([v, ol[i].chainSubject]);
      }
    } else {
      pairs.push([v, ol[i]])
    }
  }
  
  for(var i=0; i<rest.length; i++) {
    var tok = rest[i][3];
    if(!tok)
      continue;
    var newVerb  = tok[0];
    var newObjsList = tok[2] || []; // not 1 but 2 (?)
    
    for(var j=0; j<newObjsList.length; j++) {
      if(newObjsList[j].triplesContext != null) {
        triplesContext = triplesContext.concat(newObjsList[j].triplesContext);
        pairs.push([newVerb, newObjsList[j].chainSubject]);
      } else {
        pairs.push([newVerb, newObjsList[j]])
      }
    }
  }
  
  tokenParsed.pairs = pairs;
  tokenParsed.triplesContext = triplesContext;
  
  return tokenParsed;
}

// [84] VerbPath ::= Path
VerbPath = p:Path
{
  var path = {};
  path.token = 'path';
  path.kind = 'element';
  path.value = p;
  path.location = location();
  
  return p; // return path?
}

// [85] VerbSimple ::= Var
VerbSimple = Var

// [86] ObjectListPath ::= ObjectPath ( ',' ObjectPath )*
ObjectListPath = obj:ObjectPath WS* objs:(',' WS* ObjectPath)*
{
  var toReturn = [];
  
  toReturn.push(obj);
  
  for(var i=0; i<objs.length; i++) {
    for(var j=0; j<objs[i].length; j++) {
      if(typeof(objs[i][j])=="object" && objs[i][j].token != null) {
        toReturn.push(objs[i][j]);
      }
    }
  }
  
  return toReturn;
}

// [87] ObjectPath ::= GraphNodePath
ObjectPath = GraphNodePath

// [88] Path ::= PathAlternative
Path = PathAlternative

// [89] PathAlternative ::= PathSequence ( '|' PathSequence )*
PathAlternative = first:PathSequence rest:( '|' PathSequence)*
{
  if (rest == null || rest.length === 0) {
    return first;
  }
  let acum = [first];
  for (let i = 0; i < rest.length; i++) {
    acum.push(rest[i][1]);
  }
  return {
    token: 'path',
    kind: 'alternative',
    value: acum,
    location: location(),
  }
}

// [90] PathSequence ::= PathEltOrInverse ( '/' PathEltOrInverse )*
PathSequence = first:PathEltOrInverse rest:( '/' PathEltOrInverse)*
{
  if (rest == null || rest.length === 0) {
    return first;
  }
  let acum = [first];
  for (let i = 0; i < rest.length; i++) {
    acum.push(rest[i][1]);
  }
  return {
    token: 'path',
    kind: 'sequence',
    value: acum,
    location: location(),
  }
}

// [91] PathElt ::= PathPrimary PathMod?
PathElt = p:PathPrimary mod:PathMod?
{
  if (p.token && p.token != 'path' && mod == '') {
    p.kind = 'primary' // for debug
    return p;
  }
  if (p.token && p.token != 'path' && mod != '') {
    return {
      token: 'path',
      kind: 'element',
      value: p,
      modifier: mod,
    }
  } else {
    p.modifier = mod;
    return p;
  }
}

// [92] PathEltOrInverse ::= PathElt | '^' PathElt
PathEltOrInverse = PathElt
/ '^' elt:PathElt
{
    var path = {};
    path.token = 'path';
    path.kind = 'inversePath';
    path.value = elt;
    
    return path;
}

// [93] PathMod ::= '?' | '*' | '+'
// PathMod ::= ( '*' | '?' | '+' | '{' ( Integer ( ',' ( '}' | Integer '}' ) | '}' ) | ',' Integer '}' ) )
// an extension??
// PathMod = ( '*' / '?' / '+' / '{' ( Integer ( ',' ( '}' / Integer '}' ) / '}' ) / ',' Integer '}' ) )
PathMod = m:('?' / '*' / '+')
{
  return m;
}

// [94] PathPrimary ::= IRIref | 'a' | '!' PathNegatedPropertySet | '(' Path ')'
PathPrimary = IRIref
/ 'a'
{
  return{token: 'uri',  location: location(), prefix:null, suffix:null, value:"http://www.w3.org/1999/02/22-rdf-syntax-ns#type"}
}
/ '!' PathNegatedPropertySet
/ '(' p:Path ')'
{
  return p;
}

// [95] PathNegatedPropertySet ::= PathOneInPropertySet | '(' ( PathOneInPropertySet ( '|' PathOneInPropertySet )* )? ')'
PathNegatedPropertySet    = ( PathOneInPropertySet / '(' ( PathOneInPropertySet        ('|' PathOneInPropertySet)* )? ')' )

// [96] PathOneInPropertySet ::= IRIref | 'a' | '^' ( IRIref | 'a' )
PathOneInPropertySet = ( IRIref / 'a' / '^' (IRIref / 'a') )

// [97] Integer ::= INTEGER
Integer = INTEGER

// [98] TriplesNode ::= Collection | BlankNodePropertyList
TriplesNode = c:Collection
{
  var triplesContext = [];
  var chainSubject = [];

  var triple = null;

  // catch NIL
  /*
   if(c.length == 1 && c[0].token && c[0].token === 'nil') {
   GlobalBlankNodeCounter++;
   return  {token: "triplesnodecollection",
   triplesContext:[{subject: {token:'blank', value:("_:"+GlobalBlankNodeCounter)},
   predicate:{token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'},
   object:  {token:'blank', value:("_:"+(GlobalBlankNodeCounter+1))}}],
   chainSubject:{token:'blank', value:("_:"+GlobalBlankNodeCounter)}};

   }
   */

  // other cases
  for(var i=0; i<c.length; i++) {
    GlobalBlankNodeCounter++;
    //_:b0  rdf:first  1 ;
    //rdf:rest   _:b1 .
    var nextObject = null;
    if(c[i].chainSubject == null && c[i].triplesContext == null) {
      nextObject = c[i];
    } else {
      nextObject = c[i].chainSubject;
      triplesContext = triplesContext.concat(nextObject.triplesContext);
    }
    triple = {subject: {token:'blank', value:("_:"+GlobalBlankNodeCounter)},
              predicate:{token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#first'},
              object:nextObject };

    if(i==0) {
      chainSubject.push(triple.subject);
    }

    triplesContext.push(triple);

    if(i===(c.length-1)) {
      triple = {subject: {token:'blank', value:("_:"+GlobalBlankNodeCounter)},
                predicate:{token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'},
                object:   {token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#nil'}};
    } else {
      triple = {subject: {token:'blank', value:("_:"+GlobalBlankNodeCounter)},
                predicate:{token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'},
                object:  {token:'blank', value:("_:"+(GlobalBlankNodeCounter+1))} };
    }

    triplesContext.push(triple);
  }

  return {token:"triplesnodecollection", triplesContext:triplesContext, chainSubject:chainSubject};
}
/ BlankNodePropertyList

// [99] BlankNodePropertyList ::= '[' PropertyListNotEmpty ']'
BlankNodePropertyList = WS* '[' WS* pl:PropertyListNotEmpty WS* ']' WS*
{
  GlobalBlankNodeCounter++;
  var subject = {token:'blank', value:'_:'+GlobalBlankNodeCounter};
  var newTriples =  [];

  for(var i=0; i< pl.pairs.length; i++) {
    var pair = pl.pairs[i];
    var triple = {}
    triple.subject = subject;
    triple.predicate = pair[0];
    if(pair[1].length != null)
      pair[1] = pair[1][0]
    triple.object = pair[1];
    newTriples.push(triple);
  }

  return {
    token: 'triplesnode',
    location: location(),
    kind: 'blanknodepropertylist',
    triplesContext: pl.triplesContext.concat(newTriples),
    chainSubject: subject
  };
}

// [100] TriplesNodePath ::= CollectionPath | BlankNodePropertyListPath
TriplesNodePath
    = c:CollectionPath {
    var triplesContext = [];
    var chainSubject = [];

    var triple = null;

    // catch NIL
    /*
     if(c.length == 1 && c[0].token && c[0].token === 'nil') {
     GlobalBlankNodeCounter++;
     return  {token: "triplesnodecollection",
     triplesContext:[{subject: {token:'blank', value:("_:"+GlobalBlankNodeCounter)},
     predicate:{token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'},
     object:  {token:'blank', value:("_:"+(GlobalBlankNodeCounter+1))}}],
     chainSubject:{token:'blank', value:("_:"+GlobalBlankNodeCounter)}};

     }
     */

    // other cases
    for(var i=0; i<c.length; i++) {
        GlobalBlankNodeCounter++;
        //_:b0  rdf:first  1 ;
        //rdf:rest   _:b1 .
        var nextObject = null;
        if(c[i].chainSubject == null && c[i].triplesContext == null) {
            nextObject = c[i];
        } else {
            nextObject = c[i].chainSubject;
            triplesContext = triplesContext.concat(c[i].triplesContext);
        }
        triple = {
            subject: {token:'blank', value:("_:"+GlobalBlankNodeCounter)},
            predicate:{token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#first'},
            object:nextObject
        };

        if(i==0) {
            chainSubject.push(triple.subject);
        }

        triplesContext.push(triple);

        if(i===(c.length-1)) {
            triple = {subject: {token:'blank', value:("_:"+GlobalBlankNodeCounter)},
                predicate:{token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'},
                object:   {token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#nil'}};
        } else {
            triple = {subject: {token:'blank', value:("_:"+GlobalBlankNodeCounter)},
                predicate:{token:'uri', prefix:null, suffix:null, value:'http://www.w3.org/1999/02/22-rdf-syntax-ns#rest'},
                object:  {token:'blank', value:("_:"+(GlobalBlankNodeCounter+1))} };
        }

        triplesContext.push(triple);
    }

      return {token:"triplesnodecollection", triplesContext:triplesContext, chainSubject:chainSubject,  location: location()};
} / BlankNodePropertyListPath

// [101] BlankNodePropertyListPath ::= '[' PropertyListPathNotEmpty ']'
BlankNodePropertyListPath = WS* '[' WS* pl:PropertyListPathNotEmpty ']' WS*
{
  GlobalBlankNodeCounter++;
  var subject = {token:'blank', value:'_:'+GlobalBlankNodeCounter};
  var newTriples =  [];

  for(var i=0; i< pl.pairs.length; i++) {
    var pair = pl.pairs[i];
    var triple = {}
    triple.subject = subject;
    triple.predicate = pair[0];
    if(pair[1].length != null)
      pair[1] = pair[1][0]
    triple.object = pair[1];
    newTriples.push(triple);
  }

  return {
    token: 'triplesnode',
    location: location(),
    kind: 'blanknodepropertylist',
    triplesContext: pl.triplesContext.concat(newTriples),
    chainSubject: subject
  };
}

// [102] Collection ::= '(' GraphNode+ ')'
Collection = WS* '(' WS* gn:GraphNode+ WS* ')' WS*
{
  return gn;
}

// [103] CollectionPath ::= '(' GraphNodePath+ ')'
CollectionPath = WS* '(' WS* gn:GraphNodePath+ WS* ')' WS*
{
  return gn;
}

// [104] GraphNode ::= VarOrTerm | TriplesNode
GraphNode = gn:(WS* VarOrTerm WS* / WS* TriplesNode WS*)
{
  return gn[1];
}

// [105] GraphNodePath ::= VarOrTerm | TriplesNodePath
GraphNodePath =gn:(WS* VarOrTerm WS* / WS* TriplesNodePath WS*)
{
  return gn[1];
}

// [106] VarOrTerm ::= Var | GraphTerm
VarOrTerm = (Var / GraphTerm)

// [107] VarOrIri ::= Var | IRIref
VarOrIri = (Var /IRIref)

// [108] Var ::= VAR1 | VAR2
Var = WS* v:(VAR1 / VAR2 / VAR3) WS*
{
  var term = {location: location()};

  term.token = 'var';

  // term.value = v;
  term.prefix = v.prefix;
  term.value = v.value;

  return term;
}

// [109] GraphTerm ::= IRIref | RDFLiteral | NumericLiteral | BooleanLiteral | BlankNode | NIL
GraphTerm = IRIref / RDFLiteral / NumericLiteral / BooleanLiteral / BlankNode / NIL
/*
 = t:IRIref {
 var term = {};
 term.token = 'graphterm';
 term.term = 'iri';
 term.value = t;
 return term;
 }
 / t:RDFLiteral {
 var term = {};
 term.token = 'graphterm'
 term.term = 'literal'
 term.value = t
 return term;
 }
 / t:NumericLiteral {
 var term = {};
 term.token = 'graphterm'
 term.term = 'numericliteral'
 term.value = t
 return term;
 }
 / t:BooleanLiteral  {
 var term = {};
 term.token = 'graphterm'
 term.term = 'booleanliteral'
 term.value = t
 return term;
 }
 / t:BlankNode {
 var term = {};
 term.token = 'graphterm'
 term.term = 'blanknode'
 term.value = t
 return term;
 }
 / t:NIL {
 var term = {};
 term.token = 'graphterm'
 term.term = 'nil'
 term.value = t
 return term;
 }
 */

// [110] Expression ::= ConditionalOrExpression
Expression = ConditionalOrExpression

// [111] ConditionalOrExpression ::= ConditionalAndExpression ( '||' ConditionalAndExpression )*
ConditionalOrExpression = v:ConditionalAndExpression vs:(WS* '||' WS* ConditionalAndExpression)*
{
  if(vs.length === 0) {
    return v;
  }
  
  var exp = {};
  exp.token = "expression";
  exp.expressionType = "conditionalor";
  var ops = [v];
  
  for(var i=0; i<vs.length; i++) {
    ops.push(vs[i][3]);
  }
  
  exp.operands = ops;
  
  return exp;
}

// [112] ConditionalAndExpression ::= ValueLogical ( '&&' ValueLogical )*
ConditionalAndExpression = v:ValueLogical vs:(WS* '&&' WS* ValueLogical)*
{
  if(vs.length === 0) {
    return v;
  }
  var exp = {};
  exp.token = "expression";
  exp.expressionType = "conditionaland";
  var ops = [v];
  
  for(var i=0; i<vs.length; i++) {
    ops.push(vs[i][3]);
  }
  
  exp.operands = ops;
  
  return exp;
}

// [113] ValueLogical ::= RelationalExpression
ValueLogical = RelationalExpression

// [114] RelationalExpression ::= NumericExpression ( '=' NumericExpression | '!=' NumericExpression | '<' NumericExpression | '>' NumericExpression | '<=' NumericExpression | '>=' NumericExpression | 'IN' ExpressionList | 'NOT' 'IN' ExpressionList )?
RelationalExpression = op1:NumericExpression op2:(WS* '=' WS* NumericExpression /
                                                  WS* '!=' WS* NumericExpression /
                                                  WS* '<' WS* NumericExpression /
                                                  WS* '>' WS* NumericExpression /
                                                  WS* '<=' WS* NumericExpression /
                                                  WS* '>=' WS* NumericExpression /
                                                  WS* ('I'/'i')('N'/'n') WS* ExpressionList /
                                                  WS* ('N'/'n')('O'/'o')('T'/'t') WS* ('I'/'i')('N'/'n') WS* ExpressionList)*
{
  if(op2.length === 0) {
    return op1;
  } else if(op2[0][1] === 'i' || op2[0][1] === 'I' || op2[0][1] === 'n' || op2[0][1] === 'N'){
    var exp = {};
    
    if(op2[0][1] === 'i' || op2[0][1] === 'I') {
      var operator = "=";
      exp.expressionType = "conditionalor"
    } else {
      var operator = "!=";
      exp.expressionType = "conditionaland"
    }
    var lop = op1;
    var rops = []
    for(var opi=0; opi<op2[0].length; opi++) {
      if(op2[0][opi].token ==="args") {
        rops = op2[0][opi].value;
        break;
      }
    }
    
    exp.token = "expression";
    exp.operands = [];
    for(var i=0; i<rops.length; i++) {
      var nextOperand = {};
      nextOperand.token = "expression";
      nextOperand.expressionType = "relationalexpression";
      nextOperand.operator = operator;
      nextOperand.op1 = lop;
      nextOperand.op2 = rops[i];
      
      exp.operands.push(nextOperand);
    }
    return exp;
  } else {
    var exp = {};
    exp.expressionType = "relationalexpression"
    exp.operator = op2[0][1];
    exp.op1 = op1;
    exp.op2 = op2[0][3];
    exp.token = "expression";
    
    return exp;
  }
}

// [115] NumericExpression ::= AdditiveExpression
NumericExpression = AdditiveExpression

// [116] AdditiveExpression ::= MultiplicativeExpression ( '+' MultiplicativeExpression | '-' MultiplicativeExpression | ( NumericLiteralPositive | NumericLiteralNegative ) ( ( '*' UnaryExpression ) | ( '/' UnaryExpression ) )* )*
// AdditiveExpression ::= MultiplicativeExpression ( '+' MultiplicativeExpression | '-' MultiplicativeExpression | ( NumericLiteralPositive | NumericLiteralNegative ) ( ( '*' UnaryExpression ) | ( '/' UnaryExpression ) )? )*
AdditiveExpression = op1:MultiplicativeExpression ops:( WS* '+' WS* MultiplicativeExpression / WS* '-' WS* MultiplicativeExpression / ( NumericLiteralNegative / NumericLiteralNegative ) ( (WS* '*' WS* UnaryExpression) / (WS* '/' WS* UnaryExpression))? )*
{
  if(ops.length === 0) {
    return op1;
  }

  var ex = {};
  ex.token = 'expression';
  ex.expressionType = 'additiveexpression';
  ex.summand = op1;
  ex.summands = [];
  
  for(var i=0; i<ops.length; i++) {
    var summand = ops[i];
    var sum = {};
    if(summand.length == 4 && typeof(summand[1]) === "string") {
      sum.operator = summand[1];
      sum.expression = summand[3];
    } else {
      var subexp = {}
      var firstFactor = sum[0];
      var operator = sum[1][1];
      var secondFactor = sum[1][3];
      var operator = null;
      if(firstFactor.value < 0) {
        sum.operator = '-';
        firstFactor.value = - firstFactor.value;
      } else {
        sum.operator = '+';
      }
      subexp.token = 'expression';
      subexp.expressionType = 'multiplicativeexpression';
      subexp.operator = firstFactor;
      subexp.factors = [{operator: operator, expression: secondFactor}];
      
      sum.expression = subexp;
    }
    ex.summands.push(sum);
  }
  
  return ex;
}

// [117] MultiplicativeExpression ::= UnaryExpression ( '*' UnaryExpression | '/' UnaryExpression )*
MultiplicativeExpression = exp:UnaryExpression exps:(WS* '*' WS* UnaryExpression / WS* '/' WS* UnaryExpression)*
{
  if(exps.length === 0) {
    return exp;
  }
  
  var ex = {};
  ex.token = 'expression';
  ex.expressionType = 'multiplicativeexpression';
  ex.factor = exp;
  ex.factors = [];
  for(var i=0; i<exps.length; i++) {
    var factor = exps[i];
    var fact = {};
    fact.operator = factor[1];
    fact.expression = factor[3];
    ex.factors.push(fact);
  }
  
  return ex;
}

// [118] UnaryExpression ::= '!' PrimaryExpression | '+' PrimaryExpression | '-' PrimaryExpression | PrimaryExpression
UnaryExpression = '!' WS* e:PrimaryExpression
{
  return {
    token: 'expression',
    expressionType: 'unaryexpression',
    unaryexpression: "!",
    expression: e,
  }
}
/ '+' WS* v:PrimaryExpression
{
  return {
    token: 'expression',
    expressionType: 'unaryexpression',
    unaryexpression: "+",
    expression: v,
  }
}
/ '-' WS* v:PrimaryExpression
{
  return {
    token: 'expression',
    expressionType: 'unaryexpression',
    unaryexpression: "-",
    expression: v,
  }
}
/ PrimaryExpression

// [119] PrimaryExpression ::= BrackettedExpression | BuiltInCall | IRIrefOrFunction | RDFLiteral | NumericLiteral | BooleanLiteral | Var
PrimaryExpression = BrackettedExpression / BuiltInCall / IRIrefOrFunction / v:RDFLiteral
{
  return {
    token: 'expression',
    expressionType: 'atomic',
    primaryexpression: 'rdfliteral',
    value: v,
  }
}
/ v:NumericLiteral
{
  return {
    token: 'expression',
    expressionType: 'atomic',
    primaryexpression: 'numericliteral',
    value: v,
  }
}
/ v:BooleanLiteral
{
  return {
    token: 'expression',
    expressionType: 'atomic',
    primaryexpression: 'booleanliteral',
    value: v,
  }
}
/ v:Var
{
  return {
    token: 'expression',
    expressionType: 'atomic',
    primaryexpression: 'var',
    value: v,
  }
}

// [120] BrackettedExpression ::= '(' Expression ')'
BrackettedExpression = '(' WS* e:Expression WS* ')'
{
  return e;
}

// [121] BuiltInCall ::= Aggregate
//                    |  'STR' '(' Expression ')'
//                    |  'LANG' '(' Expression ')'
//                    |  'LANGMATCHES' '(' Expression ',' Expression ')'
//                    |  'DATATYPE' '(' Expression ')'
//                    |  'BOUND' '(' Var ')'
//                    |  'IRI' '(' Expression ')'
//                    |  'URI' '(' Expression ')'
//                    |  'BNODE' ( '(' Expression ')' | NIL )
//   | 'RAND' NIL
//   | 'ABS' '(' Expression ')'
//   | 'CEIL' '(' Expression ')'
//   | 'FLOOR' '(' Expression ')'
//   | 'ROUND' '(' Expression ')'
//                    | 'CONCAT' ExpressionList
//                    |  SubstringExpression
//   | 'STRLEN' '(' Expression ')'
//                    |  StrReplaceExpression
//   | 'UCASE' '(' Expression ')'
//   | 'LCASE' '(' Expression ')'
//   | 'ENCODE_FOR_URI' '(' Expression ')'
//                    | 'CONTAINS' '(' Expression ',' Expression ')'
//   | 'STRSTARTS' '(' Expression ',' Expression ')'
//   | 'STRENDS' '(' Expression ',' Expression ')'
//   | 'STRBEFORE' '(' Expression ',' Expression ')'
//                    | 'STRAFTER' '(' Expression ',' Expression ')'
//   | 'YEAR' '(' Expression ')'
//   | 'MONTH' '(' Expression ')'
//   | 'DAY' '(' Expression ')'
//   | 'HOURS' '(' Expression ')'
//   | 'MINUTES' '(' Expression ')'
//   | 'SECONDS' '(' Expression ')'
//   | 'TIMEZONE' '(' Expression ')'
//   | 'TZ' '(' Expression ')'
//   | 'NOW' NIL
//   | 'UUID' NIL
//   | 'STRUUID' NIL
//   | 'MD5' '(' Expression ')'
//   | 'SHA1' '(' Expression ')'
//   | 'SHA256' '(' Expression ')'
//   | 'SHA384' '(' Expression ')'
//   | 'SHA512' '(' Expression ')'
//                    |  'COALESCE' ExpressionList
//                    |  'IF' '(' Expression ',' Expression ',' Expression ')'
//   |  'STRLANG' '(' Expression ',' Expression ')'
//   |  'STRDT' '(' Expression ',' Expression ')'
//                    |  'sameTerm' '(' Expression ',' Expression ')'
//                    |  'isIRI' '(' Expression ')'
//                    |  'isURI' '(' Expression ')'
//                    |  'isBLANK' '(' Expression ')'
//                    |  'isLITERAL' '(' Expression ')'
//   |  'isNUMERIC' '(' Expression ')'
//                    |  RegexExpression
//                    |  ExistsFunc
//                    |  NotExistsFunc
// add custom:
BuiltInCall = Aggregate
/ 'STR'i WS* '(' WS* e:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'str',
    args: [e],
  }
}
/ 'LANG'i WS* '(' WS* e:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'lang',
    args: [e],
  }
}
/ 'LANGMATCHES'i WS* '(' WS* e1:Expression WS* ',' WS* e2:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'langmatches',
    args: [e1, e2],
  }
}
/ 'DATATYPE'i WS* '(' WS* e:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'datatype',
    args: [e],
  }
}
/ 'BOUND'i WS* '(' WS* v:Var WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'bound',
    args: [v],
  }
}
/ 'IRI'i WS* '(' WS* e:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'iri',
    args: [e],
  }
}
/ 'URI'i WS* '(' WS* e:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'uri',
    args: [e],
  }
}
/ 'BNODE'i WS* arg:('(' WS* e:Expression WS* ')' / NIL)
{
  var ex = {};
  ex.token = 'expression';
  ex.expressionType = 'builtincall';
  ex.builtincall = 'bnode';
  if(arg.length === 5) {
    ex.args = [arg[2]];
  } else {
    ex.args = null;
  }

  return ex;
}
/ 'CONCAT'i WS* args:ExpressionList
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'concat',
    args: args,
  }
}
/ SubstringExpression
/ StrReplaceExpression
/ 'CONTAINS'i WS* '(' WS* e1:Expression WS* ',' WS* e2:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'contains',
    args: [e1, e2],
  }
}
/ 'STRAFTER'i WS* '(' WS* e1:Expression WS* ',' WS* e2:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'strafter',
    args: [e1, e2],
  }
}
/ 'COALESCE'i WS* args:ExpressionList
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'coalesce',
    args: args,
  }
}
/ 'IF'i WS* '(' WS* test:Expression WS* ',' WS* trueCond:Expression WS* ',' WS* falseCond:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'if',
    args: [test, trueCond, falseCond],
  }
}
/ 'isLITERAL'i WS* '(' WS* arg:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'isliteral',
    args: [arg],
  }
}
/ 'isBLANK'i WS* '(' WS* arg:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'isblank',
    args: [arg],
  }
}
/ 'sameTerm'i WS*  '(' WS* e1:Expression WS* ',' WS* e2:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'sameterm',
    args: [e1, e2],
  }
}
/ ('isURI'i/'isIRI'i) WS* '(' WS* arg:Expression WS* ')'
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'isuri',
    args: [arg],
  }
}
/ 'custom:'i fnname:[a-zA-Z0-9_]+ WS* '(' alter:(WS* Expression ',')* WS* finalarg:Expression WS* ')'
{
  var ex = {};
  ex.token = 'expression';
  ex.expressionType = 'custom';
  ex.name = fnname.join('');
  var acum = [];
  for(var i=0; i<alter.length; i++)
    acum.push(alter[i][1]);
  acum.push(finalarg);
  ex.args = acum;

  return ex;
}
/ RegexExpression
/ ExistsFunc
/ NotExistsFunc

// [122] RegexExpression ::= 'REGEX' '(' Expression ',' Expression ( ',' Expression )? ')'
RegexExpression = 'REGEX'i WS* '(' WS* e1:Expression WS* ',' WS* e2:Expression WS* eo:( ',' WS* Expression)?  WS* ')'
{
  var regex = {};
  regex.token = 'expression';
  regex.expressionType = 'regex';
  regex.text = e1;
  regex.pattern = e2;
  if(eo != null) {
    regex.flags = eo[2];
  }
  
  return regex;
}
// [123] SubstringExpression ::= 'SUBSTR' '(' Expression ',' Expression ( ',' Expression )? ')'
SubstringExpression = 'SUBSTR'i WS* '(' WS* source:Expression WS* ',' WS* startingLoc:Expression WS* lenPart:(',' WS* len:Expression)? WS* ')'
{
  return {
      token: 'expression',
      expressionType: 'builtincall',
      builtincall: 'substr',
      args: [source, startingLoc, lenPart ? lenPart[2] : null]
  };
}
  

// [124] StrReplaceExpression ::= 'REPLACE' '(' Expression ',' Expression ',' Expression ( ',' Expression )? ')'
StrReplaceExpression = ('REPLACE'i) WS* '(' WS* arg:Expression WS* ',' WS* pattern:Expression WS* ',' WS* replacement:Expression WS* flagsPart:(',' WS* Expression)? ')'
{
  return {
      token: 'expression',
      expressionType: 'builtincall',
      builtincall: 'replace',
      args: [arg, pattern, replacement, flagsPart ? flagsPart[2] : null]
  };
}

// [125] ExistsFunc ::= 'EXISTS' GroupGraphPattern
ExistsFunc = 'EXISTS'i WS* ggp:GroupGraphPattern
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'exists',
    args: [ggp],
  }
}

// [126] NotExistsFunc ::= 'NOT' 'EXISTS' GroupGraphPattern
NotExistsFunc = 'NOT'i WS* 'EXISTS'i WS* ggp:GroupGraphPattern
{
  return {
    token: 'expression',
    expressionType: 'builtincall',
    builtincall: 'notexists',
    args: [ggp],
  }
}

// [127] Aggregate ::= 'COUNT' '(' 'DISTINCT'? ( '*' | Expression ) ')'
//       | 'SUM' '(' 'DISTINCT'? Expression ')'
//       | 'MIN' '(' 'DISTINCT'? Expression ')'
//       | 'MAX' '(' 'DISTINCT'? Expression ')'
//       | 'AVG' '(' 'DISTINCT'? Expression ')'
//       | 'SAMPLE' '(' 'DISTINCT'? Expression ')'
//       | 'GROUP_CONCAT' '(' 'DISTINCT'? Expression ( ';' 'SEPARATOR' '=' String )? ')'
// incomplete??
Aggregate = 'COUNT'i WS* '(' WS* d:('DISTINCT'i)? WS* e:('*'/Expression) WS* ')' WS*
{
  var exp = {};
  exp.token = 'expression';
  exp.expressionType = 'aggregate';
  exp.aggregateType = 'count';
  exp.distinct = ((d != "" && d != null) ? 'DISTINCT' : d);
  exp.expression = e;
  
  return exp;
}
/ 'GROUP_CONCAT'i WS* '(' WS* d:('DISTINCT'i)? WS* e:Expression s:(';' WS* 'SEPARATOR'i WS* '=' WS* String WS*)? ')' WS*
{
  var exp = {};
  exp.token = 'expression';
  exp.expressionType = 'aggregate';
  exp.aggregateType = 'group_concat';
  exp.distinct = ((d != "" && d != null) ? 'DISTINCT' : d);
  exp.expression = e;
  exp.separator = s;
  
  return exp;
}
/ 'SUM'i WS* '(' WS* d:('DISTINCT'i)? WS*  e:Expression WS* ')' WS*
{
  var exp = {};
  exp.token = 'expression';
  exp.expressionType = 'aggregate';
  exp.aggregateType = 'sum';
  exp.distinct = ((d != "" && d != null) ? 'DISTINCT' : d);
  exp.expression = e;
  
  return exp;
}
/ 'MIN'i WS* '(' WS* d:('DISTINCT'i)? WS* e:Expression WS* ')' WS*
{
  var exp = {};
  exp.token = 'expression';
  exp.expressionType = 'aggregate';
  exp.aggregateType = 'min';
  exp.distinct = ((d != "" && d != null) ? 'DISTINCT' : d);
  exp.expression = e;
  
  return exp;
}
/ 'MAX'i WS* '(' WS* d:('DISTINCT'i)? WS* e:Expression WS* ')' WS*
{
  var exp = {};
  exp.token = 'expression'
  exp.expressionType = 'aggregate'
  exp.aggregateType = 'max'
  exp.distinct = ((d != "" && d != null) ? 'DISTINCT' : d);
  exp.expression = e
  
  return exp
}
/ 'AVG'i WS* '(' WS* d:('DISTINCT'i)? WS* e:Expression WS* ')' WS*
{
  var exp = {};
  exp.token = 'expression'
  exp.expressionType = 'aggregate'
  exp.aggregateType = 'avg'
  exp.distinct = ((d != "" && d != null) ? 'DISTINCT' : d);
  exp.expression = e
  
  return exp
}
/ 'SAMPLE'i WS* '(' WS* d:('DISTINCT'i)? WS*  e:Expression WS* ')' WS*
{
  return {
    token: 'expression',
    expressionType: 'aggregate',
    aggregateType: 'sample',
    distinct: ((d != "" && d != null) ? 'DISTINCT' : d),
    expression: e,
  }
}

// [128] IRIrefOrFunction ::= IRIref ArgList?
// error?? Something has gone wrong with numeration in the rules!!
IRIrefOrFunction = i:IRIref WS* args:ArgList?
{
  var fcall = {};
  fcall.token = "expression";
  fcall.expressionType = 'irireforfunction';
  fcall.iriref = i;
  fcall.args = (args != null ? args.value : args);
  
  return fcall;
}

// [129] RDFLiteral ::= String ( LANGTAG | ( '^^' IRIref ) )?
RDFLiteral = s:String e:( LANGTAG / ('^^' IRIref) )?
{
  if(typeof(e) === "string" && e.length > 0) {
    return {token:'literal', value:s.value, lang:e.slice(1), type:null,  location: location()}
  } else {
    if(e != null && typeof(e) === "object") {
      e.shift(); // remove the '^^' char
      return {token:'literal', value:s.value, lang:null, type:e[0],  location: location()}
    } else {
      return { token:'literal', value:s.value, lang:null, type:null,  location: location() }
    }
  }
}

// [130] NumericLiteral ::= NumericLiteralUnsigned | NumericLiteralPositive | NumericLiteralNegative
NumericLiteral = NumericLiteralUnsigned / NumericLiteralPositive / NumericLiteralNegative

// [131] NumericLiteralUnsigned ::= INTEGER | DECIMAL | DOUBLE
NumericLiteralUnsigned = DOUBLE / DECIMAL / INTEGER

// [132] NumericLiteralPositive ::= INTEGER_POSITIVE | DECIMAL_POSITIVE | DOUBLE_POSITIVE
NumericLiteralPositive = DOUBLE_POSITIVE / DECIMAL_POSITIVE / INTEGER_POSITIVE

// [133] NumericLiteralNegative ::= INTEGER_NEGATIVE | DECIMAL_NEGATIVE | DOUBLE_NEGATIVE
NumericLiteralNegative = DOUBLE_NEGATIVE / DECIMAL_NEGATIVE / INTEGER_NEGATIVE

// [134] BooleanLiteral ::= 'true' | 'false'
BooleanLiteral = 'TRUE'i
{
  return {
    token: "literal",
    lang: null,
    type: "http://www.w3.org/2001/XMLSchema#boolean",
    value: true,
  }
}
/ 'FALSE'i
{
  return {
    token: "literal",
    lang: null,
    type: "http://www.w3.org/2001/XMLSchema#boolean",
    value: false,
  }
}

// [135] String ::= STRING_LITERAL1 | STRING_LITERAL2 | STRING_LITERAL_LONG1 | STRING_LITERAL_LONG2
String = s:STRING_LITERAL_LONG1 
{
  return {
    token: 'string',
    value: s,
    location: location(),
  }
}
/ s:STRING_LITERAL_LONG2 
{
  return {
    token: 'string',
    value: s,
    location: location(),
  }
}
/ s:STRING_LITERAL1 
{
  return {
    token: 'string',
    value: s,
    location: location(),
  }
}
/ s:STRING_LITERAL2 
{
  return {
    token:'string',
    value: s,
    location: location(),
  }
}

// [136] IRIref ::= IRIREF | PrefixedName
IRIref = iri:IRIREF
{
  return {
    token: 'uri',
    prefix: null,
    suffix: null,
    value: iri,
    location: location(),
  }
}
/ p:PrefixedName
{
  return p
}

// [137] PrefixedName ::= PNAME_LN | PNAME_NS
PrefixedName = p:PNAME_LN 
{
  return {
    token: 'uri',
    prefix: p[0],
    suffix: p[1],
    value: null,
    location: location(),
  }
}
/ p:PNAME_NS 
{
  return {
    token: 'uri',
    prefix: p,
    suffix: '',
    value: null,
    location: location(),
  }
}

// [138] BlankNode ::= BLANK_NODE_LABEL | ANON
BlankNode = l:BLANK_NODE_LABEL
{
  return {
    token: 'blank',
    value: l,
    location: location(),
  }
}
/ ANON 
{ 
  GlobalBlankNodeCounter++;
  return {
    token: 'blank',
    value: '_:' + GlobalBlankNodeCounter,
    location: location(),
  }
}

// [139] IRIREF ::= '<' ([^<>"{}|^`\]-[#x00-#x20])* '>'
// incomplete??
IRIREF = '<' iri_ref:[^<>\"\{\}|^`\\]* '>'
{
  return iri_ref.join('')
}

// [140] PNAME_NS ::= PN_PREFIX? ':'
PNAME_NS = p:PN_PREFIX? ':'
{
  return p
}

// [141] PNAME_LN ::= PNAME_NS PN_LOCAL
PNAME_LN = p:PNAME_NS s:PN_LOCAL
{
  return [p, s]
}

// [142] BLANK_NODE_LABEL ::= '_:' ( PN_CHARS_U | [0-9] ) ((PN_CHARS|'.')* PN_CHARS)?
// BLANK_NODE_LABEL ::= ( PN_CHARS_U | [0-9] ) ((PN_CHARS|'.')* PN_CHARS)?
// BLANK_NODE_LABEL ::= '_:' PN_LOCAL
BLANK_NODE_LABEL = '_:' l:PN_LOCAL 
{
  return l
}

// [143] VAR1 ::= '?' VARNAME
VAR1 = '?' v:VARNAME 
{
  return {
    prefix: "?",
    value: v,
  }
}

// [144] VAR2 ::= '$' VARNAME
VAR2 = '$' v:VARNAME 
{
  return {
    prefix: "$",
    value: v,
  }
}

VAR3 = '{{' v:VARNAME '}}'
{
  return {
    prefix: 'mustash',
    value: v,
  }
}

// [145] LANGTAG ::= '@' [a-zA-Z]+ ('-' [a-zA-Z0-9]+)*
LANGTAG = '@' a:[a-zA-Z]+ b:('-' [a-zA-Z0-9]+)*
{
  if(b.length===0) {
    return ("@"+a.join('')).toLowerCase();
  } else {
    return ("@"+a.join('')+"-"+b[0][1].join('')).toLowerCase();
  }
}

// [146] INTEGER ::= [0-9]+
INTEGER = d:[0-9]+
{
  return {
    token: "literal",
    lang: null,
    type: "http://www.w3.org/2001/XMLSchema#integer",
    value: flattenString(d),
  }
}

// [147] DECIMAL ::= [0-9]* '.' [0-9]+
// DECIMAL ::= [0-9]+ '.' [0-9]* | '.' [0-9]+
DECIMAL = a:[0-9]+ b:'.' c:[0-9]*
{
  return {
    token: "literal",
    lang: null,
    type: "http://www.w3.org/2001/XMLSchema#decimal",
    value: flattenString([a, b, c]),
  }
}
/ a:'.' b:[0-9]+
{
  return {
    token: "literal",
    lang: null,
    type: "http://www.w3.org/2001/XMLSchema#decimal",
    value: flattenString([a, b]),
  }
}

// [148] DOUBLE ::= [0-9]+ '.' [0-9]* EXPONENT | '.' ([0-9])+ EXPONENT | ([0-9])+ EXPONENT
DOUBLE = a:[0-9]+ b:'.' c:[0-9]* e:EXPONENT
{
  return {
    token: "literal",
    lang: null,
    type: "http://www.w3.org/2001/XMLSchema#double",
    value: flattenString([a, b, c, e]),
  }
}
/ a:'.' b:[0-9]+ c:EXPONENT
{
  return {
    token: "literal",
    lang: null,
    type: "http://www.w3.org/2001/XMLSchema#double",
    value: flattenString([a, b, c]),
  }
}
/ a:[0-9]+ b:EXPONENT
{
  return {
    token: "literal",
    lang: null,
    type: "http://www.w3.org/2001/XMLSchema#double",
    value: flattenString([a, b]),
  }
}

// [149] INTEGER_POSITIVE ::= '+' INTEGER
INTEGER_POSITIVE = '+' d:INTEGER
{
  d.value = "+" + d.value;
  return d;
}

// [150] DECIMAL_POSITIVE ::= '+' DECIMAL
DECIMAL_POSITIVE = '+' d:DECIMAL
{ d.value = "+"+d.value; return d }

// [151] DOUBLE_POSITIVE ::= '+' DOUBLE
DOUBLE_POSITIVE = '+' d:DOUBLE
{ d.value = "+"+d.value; return d }

// [152] INTEGER_NEGATIVE ::= '-' INTEGER
INTEGER_NEGATIVE = '-' d:INTEGER
{ d.value = "-"+d.value; return d; }

// [153] DECIMAL_NEGATIVE ::= '-' DECIMAL
DECIMAL_NEGATIVE = '-' d:DECIMAL
{ d.value = "-"+d.value; return d; }

// [154] DOUBLE_NEGATIVE ::= '-' DOUBLE
DOUBLE_NEGATIVE = '-' d:DOUBLE
{ d.value = "-"+d.value; return d; }

// [155] EXPONENT ::= [eE] [+-]? [0-9]+
EXPONENT = a:[eE] b:[+-]? c:[0-9]+
{ return flattenString([a,b,c]) }

// [156] STRING_LITERAL1 ::= "'" ( ([^#x27#x5C#xA#xD]) | ECHAR )* "'"
STRING_LITERAL1 = "'" content:([^\u0027\u005C\u000A\u000D] / ECHAR)* "'"
{ return flattenString(content) }

// [157] STRING_LITERAL2 ::= '"' ( ([^#x22#x5C#xA#xD]) | ECHAR )* '"'
STRING_LITERAL2 = '"' content:([^\u0022\u005C\u000A\u000D] / ECHAR)* '"'
{ return flattenString(content) }

// [158] STRING_LITERAL_LONG1 ::= "'''" ( ( "'" | "''" )? ( [^'\] | ECHAR ) )* "'''"
// check??
STRING_LITERAL_LONG1 = "'''" content:([^\'\\] / ECHAR)* "'''"
{ return flattenString(content) }

// [159] STRING_LITERAL_LONG2 ::= '"""' ( ( '"' | '""' )? ( [^"\] | ECHAR ) )* '"""'
// check??
STRING_LITERAL_LONG2 = '"""' content:([^\"\\] / ECHAR)* '"""'
{ return flattenString(content) }

// [160] ECHAR ::= '\' [tbnrf\"']
ECHAR = '\\' [tbnrf\"\']

// [161] NIL ::= '(' WS* ')'
NIL = '(' WS* ')'
{
  return {
    token: "triplesnodecollection",
    location: location(),
    triplesContext:[],
    chainSubject:[{token:'uri', value:"http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"}]};
}

// [162] WS ::= #x20 | #x9 | #xD | #xA
// WS = [\u0020] / [\u0009] / [\u000D] / [\u000A] / COMMENT
WS = COMMENT / [\u0020] / [\u0009] / [\u000D] / [\u000A]
// SPACE | TAB | CR | LF

SPACE_OR_TAB = [\u0020\u0009]
NEW_LINE = [\u000A\u000D]
NON_NEW_LINE = [^\u000A\u000D]

HEADER_LINE = h:('#' NON_NEW_LINE* NEW_LINE)
{
  return flattenString(h);
}

// COMMENT ::= '#' ( [^#xA#xD] )*
// COMMENT = comment:('#' ([^\u000A\u000D])*)
// COMMENT = comment:('#' NON_NEW_LINE*)
COMMENT = comment:(SPACE_OR_TAB* '#' NON_NEW_LINE*)
{
  var loc = location().start.line;
  // var str = flattenString(comment).trim()
  var str = flattenString(comment)
  Comments[loc] = str;

  return '';
}

// [163] ANON ::= '[' WS* ']'
ANON = '[' WS* ']'

// [164] PN_CHARS_BASE ::= [A-Z] | [a-z] | [#x00C0-#x00D6] | [#x00D8-#x00F6] | [#x00F8-#x02FF] | [#x0370-#x037D] | [#x037F-#x1FFF] | [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] | [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] | [#x10000-#xEFFFF]
PN_CHARS_BASE = [A-Z] / [a-z] / [\u00C0-\u00D6] / [\u00D8-\u00F6] / [\u00F8-\u02FF] / [\u0370-\u037D] / [\u037F-\u1FFF] / [\u200C-\u200D] / [\u2070-\u218F] / [\u2C00-\u2FEF] / [\u3001-\uD7FF] / [\uF900-\uFDCF] / [\uFDF0-\uFFFD] / [\u1000-\uEFFF]

// [165] PN_CHARS_U ::= PN_CHARS_BASE | '_'
PN_CHARS_U = PN_CHARS_BASE / '_'

// [166] VARNAME ::= ( PN_CHARS_U | [0-9] ) ( PN_CHARS_U | [0-9] | #x00B7 | [#x0300-#x036F] | [#x203F-#x2040] )*
VARNAME = init:( PN_CHARS_U / [0-9] ) rpart:( PN_CHARS_U / [0-9] / [\u00B7] / [\u0300-\u036F] / [\u203F-\u2040])*
{ return init+rpart.join('') }

// [167] PN_CHARS ::= PN_CHARS_U | '-' | [0-9] | #x00B7 | [#x0300-#x036F] | [#x203F-#x2040]
PN_CHARS = PN_CHARS_U / '-' / [0-9] / [\u00B7] / [\u0300-\u036F] / [\u203F-\u2040]

// [168] PN_PREFIX ::= PN_CHARS_BASE ((PN_CHARS|'.')* PN_CHARS)?
// PN_PREFIX = base:PN_CHARS_BASE rest:(PN_CHARS / '.')*
// add '_'
PN_PREFIX = base:PN_CHARS_U rest:(PN_CHARS / '.')*
{ 
  if(rest[rest.length-1] == '.'){
    throw new Error("Wrong PN_PREFIX, cannot finish with '.'")
  } else {
    return base + rest.join('');
  }
}

// [169] PN_LOCAL ::= (PN_CHARS_U | ':' | [0-9] | PLX ) ((PN_CHARS | '.' | ':' | PLX)* (PN_CHARS | ':' | PLX) )?
// similar to BLANK_NODE_LABEL??
// base:(PN_CHARS_U / [0-9] / ':' / PLX) rest:((PN_CHARS / '.' / ':' / PLX)* (PN_CHARS / ':' / PLX))?
  // '$' is added
  // still missing something at the end??
PN_LOCAL = base:('$' / PN_CHARS_U / [0-9] / ':' / PLX) rest:(PN_CHARS / '.' / ':' / PLX)* 
{
  return base + (rest||[]).join('');
}

// [170] PLX ::= PERCENT | PN_LOCAL_ESC
PLX = PERCENT / PN_LOCAL_ESC

// [171] PERCENT ::= '%' HEX HEX
PERCENT = h:('%' HEX HEX)
{
  return h.join("");
}

// [172] HEX ::= [0-9] | [A-F] | [a-f]
HEX = [0-9] / [A-F] / [a-f]

// [173] PN_LOCAL_ESC ::= '\' ( '_' | '~' | '.' | '-' | '!' | '$' | '&' | "'" | '(' | ')' | '*' | '+' | ',' | ';' | '=' | '/' | '?' | '#' | '@' | '%' )
PN_LOCAL_ESC = '\\' c:( '_' / '~' / '.' / '-' / '!' / '$' / '&' / "'" / '(' / ')' / '*' / '+' / ',' / ';' / ':' / '=' / '/' / '?' / '#' / '@' / '%' )
{
  return "\\"+c;
}
