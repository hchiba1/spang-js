# SPANG

## SPARQL client

`spang2` is a commmand-line SPARQL client. It is now re-implemented in JavaScript, and comes with new features.

### Installation
```
$ git clone git@github.com/hchiba1/spang.git
$ cd spang
$ npm install
$ npm link
```

### Usage
```
SPANG v2.0.0: Specify a SPARQL query (template or shortcut).

Usage: spang2 [options] [SPARQL_TEMPLATE] [par1=val1,par2=val2,...]

Options:
  -e, --endpoint <ENDPOINT>    target SPARQL endpoint (URL or its predifined name in SPANG_DIR/etc/endpoints,~/.spang/endpoints)
  -p, --param <PARAMS>         parameters to be embedded (in the form of "--param par1=val1,par2=val2,...")
  -o, --outfmt <FORMAT>        tsv, json, n-triples (nt), turtle (ttl), rdf/xml (rdfxml), n3, xml, html (default: "tsv")
  -a, --abbr                   abbreviate results using predefined prefixes
  -v, --vars                   variable names are included in output (in the case of tsv format)
  -S, --subject <SUBJECT>      shortcut to specify subject
  -P, --predicate <PREDICATE>  shortcut to specify predicate
  -O, --object <OBJECT>        shortcut to specify object
  -L, --limit <LIMIT>          LIMIT output (use alone or with -[SPOF])
  -F, --from <FROM>            shortcut to search FROM specific graph (use alone or with -[SPOLN])
  -N, --number                 shortcut to COUNT results (use alone or with -[SPO])
  -G, --graph                  shortcut to search for graph names (use alone or with -[SPO])
  -r, --prefix <PREFIX_FILES>  read prefix declarations (default: SPANG_DIR/etc/prefix,~/.spang/prefix)
  -n, --ignore                 ignore user-specific file (~/.spang/prefix) for test purpose
  -m, --method <METHOD>        GET or POST (default: "GET")
  -q, --show_query             show query and quit
  -f, --fmt                    format the query
  -i, --indent <DEPTH>         indent depth; use with --fmt (default: 2)
  -l, --list_nick_name         list up available nicknames of endpoints and quit
  -d, --debug                  debug (output query embedded in URL, or output AST with --fmt)
  --time                       measure time of query execution (exluding construction of query)
  -V, --version                output the version number
  -h, --help                   display help for command
```
### Test examples
```
$ npm test
```

### Update spang.js
Update the `js/spang.js` as follows after editing any other JS codes
```
$ npm run browserify
```

## SPARQL formatter

`spfmt` is a SPARQL formatter written in JavaScript.

It can be used in a web site or in the command line.

An example web site:<br>
https://spang.dbcls.jp/example.html

### Usage on a web site

* Download `spfmt.js` and use it in your HTML.

```
<script src="/js/spfmt.js"></script>
```

* Then you can use `spfmt`.
```javascript
spfmt("SELECT * WHERE {?s ?p ?o}");
/*
SELECT *
WHERE {
  ?s ?p ?o .
}
*/
```

* You can also call `spfmt.js` through the jsDelivr service.
```
    <textarea id="sparql-text" rows=5></textarea>
    <button id="reformat-button">Reformat</button>
    <textarea id="sparql-text-after" rows=5></textarea>
    
    <script src="https://cdn.jsdelivr.net/gh/sparqling/spang@master/js/spfmt.js"></script>
    <script type="text/javascript">
     window.onload = () => {
         var textArea = 
             document.querySelector("#reformat-button").addEventListener('click', (event) => {
                 document.querySelector("#sparql-text-after").value =
                     spfmt(document.querySelector("#sparql-text").value);
             });
     };
    </script>
```
### Usage in command line

#### Requirements
- Node.js (>= 11.0.0)
- npm (>= 6.12.0)

#### Installation
```
$ npm install
$ npm link
```

#### Usage
```
$ cat messy.rq 
SELECT * WHERE         {         ?s ?p ?o }

$ spfmt messy.rq 
SELECT *
WHERE {
    ?s ?p ?o .
}
```

#### Test examples
If you have globally installed mocha

```
$ npm test
```

### Update spfmt.js
`js/spfmt.js` should be updated as follows after after modifying parser or formatter codes.
```
$ npm run browserify
```

## SPARQL specifications

### Syntax
The EBNF notation of SPARQL is extracted from:<br>
https://www.w3.org/TR/sparql11-query/#sparqlGrammar

The PEG expression of SPARQL grammer was originally provided by:<br>
https://github.com/antoniogarrote/rdfstore-js/

PEG can be tested at:<br>
https://pegjs.org/online

### Medadata
[sparql-doc](https://github.com/ldodds/sparql-doc)
```
# @title Get orthololog from MBGD
# @author Hirokazu Chiba
# @tag ortholog
# @endpoint http://sparql.nibb.ac.jp/sparql
```
extension
```
# @prefixes https://
# @input_class id:Taxon
# @output_class up:Protein
# @param gene=
```
