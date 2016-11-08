# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  let(:logger) {RDF::Spec.logger}

  describe ".frame" do
    {
      "exact @type match" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": "ex:Type1"
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }]
        })
      },
      "wildcard @type match" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": {}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }]
        })
      },
      "match none @type match" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": []
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:p": "Foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:p": "Bar"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub2",
            "ex:p": "Bar"
          }]
        })
      },
      "multiple matches on @type" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": "ex:Type1"
        }),
        input: %([{
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1"
        }, {
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub2",
          "@type": "ex:Type1"
        }, {
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub3",
          "@type": ["ex:Type1", "ex:Type2"]
        }]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@id": "ex:Sub2",
            "@type": "ex:Type1"
          }, {
            "@id": "ex:Sub3",
            "@type": ["ex:Type1", "ex:Type2"]
          }]
        })
      },
      "single @id match" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1"
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }]
        })
      },
      "multiple @id match" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": ["ex:Sub1", "ex:Sub2"]
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub3",
            "@type": "ex:Type3"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@id": "ex:Sub2",
            "@type": "ex:Type2"
          }]
        })
      },
      "wildcard and match none" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "ex:p": [],
          "ex:q": {}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:q": "bar"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:p": "foo",
            "ex:q": "bar"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": null,
            "ex:q": "bar"
          }]
        })
      },
      "match on any property if @requireAll is false" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@requireAll": false,
          "ex:p": {},
          "ex:q": {}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:q": "bar"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "foo",
            "ex:q": null
          }, {
            "@id": "ex:Sub2",
            "ex:p": null,
            "ex:q": "bar"
          }]
        })
      },
      "match on defeaults if @requireAll is true and at least one property matches" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@requireAll": true,
          "ex:p": {"@default": "Foo"},
          "ex:q": {"@default": "Bar"}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:q": "bar"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub3",
            "ex:p": "foo",
            "ex:q": "bar"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub4",
            "ex:r": "baz"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "foo",
            "ex:q": "Bar"
          }, {
            "@id": "ex:Sub2",
            "ex:p": "Foo",
            "ex:q": "bar"
          }, {
            "@id": "ex:Sub3",
            "ex:p": "foo",
            "ex:q": "bar"
          }]
        })
      },
      "match with @requireAll with one default" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@requireAll": true,
          "ex:p": {},
          "ex:q": {"@default": "Bar"}
        }),
        input: %([
          {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "ex:p": "foo"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub2",
            "ex:q": "bar"
          }, {
            "@context": { "ex":"http://example.org/"},
            "@id": "ex:Sub3",
            "ex:p": "foo",
            "ex:q": "bar"
          }
        ]),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "foo",
            "ex:q": "Bar"
          }, {
            "@id": "ex:Sub3",
            "ex:p": "foo",
            "ex:q": "bar"
          }]
        })
      },
      "implicitly includes unframed properties (default @explicit false)" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": "ex:Type1"
        }),
        input: %q({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:prop1": "Property 1",
            "ex:prop2": {"@id": "ex:Obj1"}
          }]
        })
      },
      "explicitly includes unframed properties @explicit false" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@explicit": false,
          "@type": "ex:Type1"
        }),
        input: %q({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:prop1": "Property 1",
            "ex:prop2": {"@id": "ex:Obj1"}
          }]
        })
      },
      "explicitly excludes unframed properties (@explicit: true)" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@explicit": true,
          "@type": "ex:Type1"
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }]
        })
      },
      "non-existent framed properties create null property" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@type": "ex:Type1",
          "ex:null": []
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }),
        output: %({
          "@context": {
            "ex": "http://example.org/"
          },
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:prop1": "Property 1",
            "ex:prop2": {
              "@id": "ex:Obj1"
            },
            "ex:null": null
          }]
        })
      },
      "non-existent framed properties create default property" => {
        frame: %({
          "@context": {
            "ex": "http://example.org/",
            "ex:null": {"@container": "@set"}
          },
          "@type": "ex:Type1",
          "ex:null": [{"@default": "foo"}]
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:prop1": "Property 1",
          "ex:prop2": {"@id": "ex:Obj1"}
        }),
        output: %({
          "@context": {
            "ex": "http://example.org/",
            "ex:null": {"@container": "@set"}
          },
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:prop1": "Property 1",
            "ex:prop2": {"@id": "ex:Obj1"},
            "ex:null": ["foo"]
          }]
        }
        )
      },
      "mixed content" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "ex:mixed": {"@embed": false}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:mixed": [
            {"@id": "ex:Sub2"},
            "literal1"
          ]
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:mixed": [
              {"@id": "ex:Sub2"},
              "literal1"
            ]
          }]
        })
      },
      "no embedding (@embed: false)" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "ex:embed": {"@embed": false}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:embed": {
            "@id": "ex:Sub2",
            "ex:prop": "property"
          }
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:embed": {"@id": "ex:Sub2"}
          }]
        })
      },
      "mixed list" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "ex:mixedlist": {}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "@type": "ex:Type1",
          "ex:mixedlist": {
            "@list": [
              {"@id": "ex:Sub2", "@type": "ex:Type2"},
              "literal1"
            ]
          }
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "@type": "ex:Type1",
            "ex:mixedlist": {
              "@list": [
                {"@id": "ex:Sub2", "@type": "ex:Type2"},
                "literal1"
              ]
            }
          }]
        })
      },
      "presentation example" => {
        frame: %({
          "@context": {
            "primaryTopic": {
              "@id": "http://xmlns.com/foaf/0.1/primaryTopic",
              "@type": "@id"
            },
            "sameAs": {
              "@id": "http://www.w3.org/2002/07/owl#sameAs",
              "@type": "@id"
            }
          },
          "primaryTopic": {
            "@type": "http://dbpedia.org/class/yago/Buzzwords",
            "sameAs": {}
          }
        }),
        input: %([{
          "@id": "http://en.wikipedia.org/wiki/Linked_Data",
          "http://xmlns.com/foaf/0.1/primaryTopic": {"@id": "http://dbpedia.org/resource/Linked_Data"}
        }, {
          "@id": "http://www4.wiwiss.fu-berlin.de/flickrwrappr/photos/Linked_Data",
          "http://www.w3.org/2002/07/owl#sameAs": {"@id": "http://dbpedia.org/resource/Linked_Data"}
        }, {
          "@id": "http://dbpedia.org/resource/Linked_Data",
          "@type": "http://dbpedia.org/class/yago/Buzzwords",
          "http://www.w3.org/2002/07/owl#sameAs": {"@id": "http://rdf.freebase.com/ns/m/02r2kb1"}
        }, {
          "@id": "http://mpii.de/yago/resource/Linked_Data",
          "http://www.w3.org/2002/07/owl#sameAs": {"@id": "http://dbpedia.org/resource/Linked_Data"}
        }
      ]),
        output: %({
          "@context": {
            "primaryTopic": {"@id": "http://xmlns.com/foaf/0.1/primaryTopic", "@type": "@id"},
            "sameAs": {"@id": "http://www.w3.org/2002/07/owl#sameAs", "@type": "@id"}
          },
          "@graph": [{
            "@id": "http://en.wikipedia.org/wiki/Linked_Data",
            "primaryTopic": {
              "@id": "http://dbpedia.org/resource/Linked_Data",
              "@type": "http://dbpedia.org/class/yago/Buzzwords",
              "sameAs": "http://rdf.freebase.com/ns/m/02r2kb1"
            }
          }]
        })
      },
      "microdata manifest" => {
        frame: %({
          "@context": {
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "mf": "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
            "mq": "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
            "comment": "rdfs:comment",
            "entries": {"@id": "mf:entries", "@container": "@list"},
            "name": "mf:name",
            "action": "mf:action",
            "data": {"@id": "mq:data", "@type": "@id"},
            "query": {"@id": "mq:query", "@type": "@id"},
            "result": {"@id": "mf:result", "@type": "xsd:boolean"}
          },
          "@type": "mf:Manifest",
          "entries": [{
            "@type": "mf:ManifestEntry",
            "action": {
              "@type": "mq:QueryTest"
            }
          }]
        }),
        input: %q({
          "@context": {
            "md": "http://www.w3.org/ns/md#",
            "mf": "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
            "mq": "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#"
          },
          "@graph": [{
            "@id": "_:manifest",
            "@type": "mf:Manifest",
            "mf:entries": {"@list": [{"@id": "_:entry"}]},
            "rdfs:comment": "Positive processor tests"
          }, {
            "@id": "_:entry",
            "@type": "mf:ManifestEntry",
            "mf:action": {"@id": "_:query"},
            "mf:name": "Test 0001",
            "mf:result": "true",
            "rdfs:comment": "Item with no itemtype and literal itemprop"
          }, {
            "@id": "_:query",
            "@type": "mq:QueryTest",
            "mq:data": {"@id": "http://www.w3.org/TR/microdata-rdf/tests/0001.html"},
            "mq:query": {"@id": "http://www.w3.org/TR/microdata-rdf/tests/0001.ttl"}
          }]
        }),
        output: %({
          "@context": {
            "xsd": "http://www.w3.org/2001/XMLSchema#",
            "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
            "mf": "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#",
            "mq": "http://www.w3.org/2001/sw/DataAccess/tests/test-query#",
            "comment": "rdfs:comment",
            "entries": {"@id": "mf:entries","@container": "@list"},
            "name": "mf:name",
            "action": "mf:action",
            "data": {"@id": "mq:data", "@type": "@id"},
            "query": {"@id": "mq:query", "@type": "@id"},
            "result": {"@id": "mf:result", "@type": "xsd:boolean"}
          },
          "@graph": [{
            "@id": "_:b0",
            "@type": "mf:Manifest",
            "comment": "Positive processor tests",
            "entries": [{
              "@id": "_:b1",
              "@type": "mf:ManifestEntry",
              "action": {
                "@id": "_:b2",
                "@type": "mq:QueryTest",
                "data": "http://www.w3.org/TR/microdata-rdf/tests/0001.html",
                "query": "http://www.w3.org/TR/microdata-rdf/tests/0001.ttl"
              },
              "comment": "Item with no itemtype and literal itemprop",
              "mf:result": "true",
              "name": "Test 0001"
            }]
          }]
        })
      }
    }.each do |title, params|
      it title do
        do_frame(params)
      end
    end

    describe "@reverse" do
      {
        "embed matched frames with @reverse" => {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "@type": "ex:Type1",
            "@reverse": {"ex:includes": {}}
          }),
          input: %([{
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2",
            "ex:includes": {"@id": "ex:Sub1"}
          }]),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "@type": "ex:Type1",
              "@reverse": {
                "ex:includes": {
                  "@id": "ex:Sub2",
                  "@type": "ex:Type2",
                  "ex:includes": {
                    "@id": "ex:Sub1"
                  }
                }
              }
            }]
          })
        },
        "embed matched frames with reversed property" => {
          frame: %({
            "@context": {
              "ex": "http://example.org/",
              "excludes": {"@reverse": "ex:includes"}
            },
            "@type": "ex:Type1",
            "excludes": {}
          }),
          input: %([{
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub1",
            "@type": "ex:Type1"
          }, {
            "@context": {"ex": "http://example.org/"},
            "@id": "ex:Sub2",
            "@type": "ex:Type2",
            "ex:includes": {"@id": "ex:Sub1"}
          }]),
          output: %({
            "@context": {
              "ex": "http://example.org/",
              "excludes": {"@reverse": "ex:includes"}
            },
            "@graph": [{
              "@id": "ex:Sub1",
              "@type": "ex:Type1",
              "excludes": {
                "@id": "ex:Sub2",
                "@type": "ex:Type2",
                "ex:includes": {"@id": "ex:Sub1"}
              }
            }]
          })
        },
      }.each do |title, params|
        it title do
          begin
            input, frame, output = params[:input], params[:frame], params[:output]
            input = ::JSON.parse(input) if input.is_a?(String)
            frame = ::JSON.parse(frame) if frame.is_a?(String)
            output = ::JSON.parse(output) if output.is_a?(String)
            jld = JSON::LD::API.frame(input, frame, logger: logger)
            expect(jld).to produce(output, logger)
          rescue JSON::LD::JsonLdError, JSON::LD::JsonLdError, JSON::LD::InvalidFrame => e
            fail("#{e.class}: #{e.message}\n" +
              "#{logger}\n" +
              "Backtrace:\n#{e.backtrace.join("\n")}")
          end
        end
      end
    end

    describe "node pattern" do
      {
        "matches a deep node pattern" => {
          frame: %({
            "@context": {"ex": "http://example.org/"},
            "ex:p": {
              "ex:q": {}
            }
          }),
          input: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "@type": "ex:Type1",
              "ex:p": {
                "@id": "ex:Sub2",
                "@type": "ex:Type2",
                "ex:q": "foo"
              }
            }, {
              "@id": "ex:Sub3",
              "@type": "ex:Type1",
              "ex:q": {
                "@id": "ex:Sub4",
                "@type": "ex:Type2",
                "ex:r": "bar"
              }
            }]
          }),
          output: %({
            "@context": {"ex": "http://example.org/"},
            "@graph": [{
              "@id": "ex:Sub1",
              "@type": "ex:Type1",
              "ex:p": {
                "@id": "ex:Sub2",
                "@type": "ex:Type2",
                "ex:q": "foo"
              }
            }]
          })
        },
      }.each do |title, params|
        it title do
          do_frame(params)
        end
      end
    end
  end

  describe "value pattern" do
    {
      "matches exact values" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": "P",
          "ex:q": {"@value": "Q", "@type": "ex:q"},
          "ex:r": {"@value": "R", "@language": "r"}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": "P",
          "ex:q": {"@value": "Q", "@type": "ex:q"},
          "ex:r": {"@value": "R", "@language": "r"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }]
        })
      },
      "matches wildcard @value" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": {"@value": {}},
          "ex:q": {"@value": {}, "@type": "ex:q"},
          "ex:r": {"@value": {}, "@language": "r"}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": "P",
          "ex:q": {"@value": "Q", "@type": "ex:q"},
          "ex:r": {"@value": "R", "@language": "r"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }]
        })
      },
      "matches wildcard @type" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:q": {"@value": "Q", "@type": {}}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:q": {"@value": "Q", "@type": "ex:q"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:q": {"@value": "Q", "@type": "ex:q"}
          }]
        })
      },
      "matches wildcard @language" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:r": {"@value": "R", "@language": {}}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:r": {"@value": "R", "@language": "r"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:r": {"@value": "R", "@language": "r"}
          }]
        })
      },
      "match none @type" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": {"@value": {}, "@type": []},
          "ex:q": {"@value": {}, "@type": "ex:q"},
          "ex:r": {"@value": {}, "@language": "r"}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": "P",
          "ex:q": {"@value": "Q", "@type": "ex:q"},
          "ex:r": {"@value": "R", "@language": "r"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }]
        })
      },
      "match none @language" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": {"@value": {}, "@language": []},
          "ex:q": {"@value": {}, "@type": "ex:q"},
          "ex:r": {"@value": {}, "@language": "r"}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": "P",
          "ex:q": {"@value": "Q", "@type": "ex:q"},
          "ex:r": {"@value": "R", "@language": "r"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }]
        })
      },
      "matches some @value" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": {"@value": ["P", "Q", "R"]},
          "ex:q": {"@value": ["P", "Q", "R"], "@type": "ex:q"},
          "ex:r": {"@value": ["P", "Q", "R"], "@language": "r"}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": "P",
          "ex:q": {"@value": "Q", "@type": "ex:q"},
          "ex:r": {"@value": "R", "@language": "r"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }]
        })
      },
      "matches some @type" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:q": {"@value": "Q", "@type": ["ex:q", "ex:Q"]}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:q": {"@value": "Q", "@type": "ex:q"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:q": {"@value": "Q", "@type": "ex:q"}
          }]
        })
      },
      "matches some @language" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:r": {"@value": "R", "@language": ["p", "q", "r"]}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:r": {"@value": "R", "@language": "r"}
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:r": {"@value": "R", "@language": "r"}
          }]
        })
      },
      "excludes non-matched values" => {
        frame: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": {"@value": {}},
          "ex:q": {"@value": {}, "@type": "ex:q"},
          "ex:r": {"@value": {}, "@language": "R"}
        }),
        input: %({
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:Sub1",
          "ex:p": ["P", {"@value": "P", "@type": "ex:p"}, {"@value": "P", "@language": "P"}],
          "ex:q": ["Q", {"@value": "Q", "@type": "ex:q"}, {"@value": "Q", "@language": "Q"}],
          "ex:r": ["R", {"@value": "R", "@type": "ex:r"}, {"@value": "R", "@language": "R"}]
        }),
        output: %({
          "@context": {"ex": "http://example.org/"},
          "@graph": [{
            "@id": "ex:Sub1",
            "ex:p": "P",
            "ex:q": {"@value": "Q", "@type": "ex:q"},
            "ex:r": {"@value": "R", "@language": "r"}
          }]
        })
      },
    }.each do |title, params|
      it title do
        do_frame(params)
      end
    end
  end

  context "problem cases" do
    it "pr #20" do
      expanded = [
        {
          "@id"=>"_:gregg",
          "@type"=>"http://xmlns.com/foaf/0.1/Person",
          "http://xmlns.com/foaf/0.1/name" => "Gregg Kellogg"
        }, {
          "@id"=>"http://manu.sporny.org/#me",
          "@type"=> "http://xmlns.com/foaf/0.1/Person",
          "http://xmlns.com/foaf/0.1/knows"=> {"@id"=>"_:gregg"},
          "http://xmlns.com/foaf/0.1/name"=>"Manu Sporny"
        }
      ]
      framed = JSON::LD::API.frame(expanded, {})
      data = framed["@graph"].first
      expect(data["mising_value"]).to be_nil
    end

    it "issue #28" do
      input = JSON.parse %({
        "@context": {
          "rdfs": "http://www.w3.org/2000/01/rdf-schema#"
        },
        "@id": "http://www.myresource/uuid",
        "http://www.myresource.com/ontology/1.0#talksAbout": [
          {
            "@id": "http://rdf.freebase.com/ns/m.018w8",
            "rdfs:label": [
              {
                "@value": "Basketball",
                "@language": "en"
              }
            ]
          }
        ]
      })
      frame = JSON.parse %({
        "@context": {
          "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
          "talksAbout": {
            "@id": "http://www.myresource.com/ontology/1.0#talksAbout",
            "@type": "@id"
          },
          "label": {
            "@id": "rdfs:label",
            "@language": "en"
          }
        },
        "@id": "http://www.myresource/uuid"
      })
      expected = JSON.parse %({
        "@context": {
          "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
          "talksAbout": {
            "@id": "http://www.myresource.com/ontology/1.0#talksAbout",
            "@type": "@id"
          },
          "label": {
            "@id": "rdfs:label",
            "@language": "en"
          }
        },
        "@graph": [
          {
            "@id": "http://www.myresource/uuid",
            "talksAbout": {
              "@id": "http://rdf.freebase.com/ns/m.018w8",
              "label": "Basketball"
            }
          }
        ]
      })
      do_frame(input: input, frame: frame, output: expected)
    end
  end

  def do_frame(params)
    begin
      input, frame, output = params[:input], params[:frame], params[:output]
      input = ::JSON.parse(input) if input.is_a?(String)
      frame = ::JSON.parse(frame) if frame.is_a?(String)
      output = ::JSON.parse(output) if output.is_a?(String)
      jld = JSON::LD::API.frame(input, frame, logger: logger)
      expect(jld).to produce(output, logger)
    rescue JSON::LD::JsonLdError, JSON::LD::JsonLdError, JSON::LD::InvalidFrame => e
      fail("#{e.class}: #{e.message}\n" +
        "#{logger}\n" +
        "Backtrace:\n#{e.backtrace.join("\n")}")
    end
  end
end
