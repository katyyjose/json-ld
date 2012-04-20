# coding: utf-8
$:.unshift "."
require 'spec_helper'
require 'rdf/spec/reader'

describe JSON::LD::EvaluationContext do
  before(:each) {
    @debug = []
    @ctx_json = %q({
      "@context": {
        "name": "http://xmlns.com/foaf/0.1/name",
        "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
        "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
      }
    })
  }
  subject { JSON::LD::EvaluationContext.new(:debug => @debug, :validate => true)}

  describe "#parse" do
    context "remote" do
      before(:each) do
        @ctx = StringIO.new(@ctx_json)
        def @ctx.content_type; "application/ld+json"; end
      end

      it "retrieves and parses a remote context document" do
        RDF::Util::File.stub(:open_file).with("http://example.com/context").and_yield(@ctx)
        ec = subject.parse("http://example.com/context")
        ec.provided_context.should produce("http://example.com/context", @debug)
      end

      it "fails given a missing remote @context" do
        RDF::Util::File.stub(:open_file).with("http://example.com/context").and_raise(IOError)
        lambda {subject.parse("http://example.com/context")}.should raise_error(JSON::LD::InvalidContext, /Failed to parse remote context/)
      end

      it "creates mappings" do
        RDF::Util::File.stub(:open_file).with("http://example.com/context").and_yield(@ctx)
        ec = subject.parse("http://example.com/context")
        ec.mappings.should produce({
          "name"     => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar"   => "http://xmlns.com/foaf/0.1/avatar"
        }, @debug)
      end
    end

    context "EvaluationContext" do
      it "uses a duplicate of that provided" do
        ec = subject.parse(StringIO.new(@ctx_json))
        ec.mappings.should produce({
          "name"     => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar"   => "http://xmlns.com/foaf/0.1/avatar"
        }, @debug)
      end
    end

    context "Array" do
      before(:all) do
        @ctx = [
          {"foo" => "http://example.com/foo"},
          {"bar" => "foo"}
        ]
      end

      it "merges definitions from each context" do
        ec = subject.parse(@ctx)
        ec.mappings.should produce({
          "foo" => "http://example.com/foo",
          "bar" => "http://example.com/foo"
        }, @debug)
      end
    end

    context "Hash" do
      it "extracts @language" do
        subject.parse({
          "@language" => "en"
        }).default_language.should produce("en", @debug)
      end

      it "maps term with IRI value" do
        subject.parse({
          "foo" => "http://example.com/"
        }).mappings.should produce({
          "foo" => "http://example.com/"
        }, @debug)
      end

      it "maps term with @id" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/"}
        }).mappings.should produce({
          "foo" => "http://example.com/"
        }, @debug)
      end

      it "associates @list coercion with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@container" => "@list"}
        }).containers.should produce({
          "foo" => '@list'
        }, @debug)
      end

      it "associates @set coercion with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@container" => "@set"}
        }).containers.should produce({
          "foo" => '@set'
        }, @debug)
      end

      it "associates @id coercion with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@type" => "@id"}
        }).coercions.should produce({
          "foo" => "@id"
        }, @debug)
      end

      it "associates datatype coercion with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@type" => RDF::XSD.string.to_s}
        }).coercions.should produce({
          "foo" => RDF::XSD.string.to_s
        }, @debug)
      end

      it "associates language coercion with predicate" do
        subject.parse({
          "foo" => {"@id" => "http://example.com/", "@language" => "en"}
        }).languages.should produce({
          "foo" => "en"
        }, @debug)
      end

      it "expands chains of term definition/use with string values" do
        subject.parse({
          "foo" => "bar",
          "bar" => "baz",
          "baz" => "http://example.com/"
        }).mappings.should produce({
          "foo" => "http://example.com/",
          "bar" => "http://example.com/",
          "baz" => "http://example.com/"
        }, @debug)
      end

      context "with null" do
        it "removes @language if set to null" do
          subject.parse([
            {
              "@language" => "en"
            },
            {
              "@language" => nil
            }
          ]).default_language.should produce(nil, @debug)
        end

        it "loads initial context" do
          init_ec = JSON::LD::EvaluationContext.new
          nil_ec = subject.parse(nil)
          nil_ec.default_language.should == init_ec.default_language
          nil_ec.languages.should == init_ec.languages
          nil_ec.mappings.should == init_ec.mappings
          nil_ec.coercions.should == init_ec.coercions
          nil_ec.containers.should == init_ec.containers
        end
        
        it "removes a term definition" do
          subject.parse({"name" => nil}).mapping("name").should be_nil
        end
      end
    end

    describe "Syntax Errors" do
      {
        "malformed JSON" => StringIO.new(%q({"@context": {"foo" "http://malformed/"})),
        "no @id, @type, or @container" => {"foo" => {}},
        "value as array" => {"foo" => []},
        "@id as object" => {"foo" => {"@id" => {}}},
        "@id as array" => {"foo" => {"@id" => []}},
        "@type as object" => {"foo" => {"@type" => {}}},
        "@type as array" => {"foo" => {"@type" => []}},
        "@type as @list" => {"foo" => {"@type" => "@list"}},
        "@type as @list" => {"foo" => {"@type" => "@set"}},
        "@container as object" => {"foo" => {"@container" => {}}},
        "@container as array" => {"foo" => {"@container" => []}},
        "@container as string" => {"foo" => {"@container" => "true"}},
      }.each do |title, context|
        it title do
          #subject.parse(context)
          lambda {
            ec = subject.parse(context)
            ec.serialize.should produce({}, @debug)
          }.should raise_error(JSON::LD::InvalidContext::Syntax)
        end
      end
    end

    describe "Load Errors" do
      {
        "fixme" => "FIXME",
      }.each do |title, context|
        it title do
          lambda { subject.parse(context) }.should raise_error(JSON::LD::InvalidContext::LoadError)
        end
      end
    end
  end

  describe "#serialize" do
    it "uses provided context document" do
      ctx = StringIO.new(@ctx_json)
      def ctx.content_type; "application/ld+json"; end

      RDF::Util::File.stub(:open_file).with("http://example.com/context").and_yield(ctx)
      ec = subject.parse("http://example.com/context")
      ec.serialize.should produce({
        "@context" => "http://example.com/context"
      }, @debug)
    end

    it "uses provided context array" do
      ctx = [
        {"foo" => "http://example.com/"},
        {"baz" => "bob"}
      ]

      ec = subject.parse(ctx)
      ec.serialize.should produce({
        "@context" => ctx
      }, @debug)
    end

    it "uses provided context hash" do
      ctx = {"foo" => "http://example.com/"}

      ec = subject.parse(ctx)
      ec.serialize.should produce({
        "@context" => ctx
      }, @debug)
    end

    it "@language" do
      subject.default_language = "en"
      subject.serialize.should produce({
        "@context" => {
          "@language" => "en"
        }
      }, @debug)
    end

    it "term mappings" do
      subject.set_mapping("foo", RDF::URI("http://example.com/"))
      subject.serialize.should produce({
        "@context" => {
          "foo" => "http://example.com/"
        }
      }, @debug)
    end

    it "@type with dependent prefixes in a single context" do
      subject.set_mapping("xsd", RDF::XSD.to_uri)
      subject.set_mapping("homepage", RDF::FOAF.homepage)
      subject.set_coerce("homepage", "@id")
      subject.serialize.should produce({
        "@context" => {
          "xsd" => RDF::XSD.to_uri,
          "homepage" => {"@id" => RDF::FOAF.homepage.to_s, "@type" => "@id"}
        }
      }, @debug)
    end

    it "@list with @id definition in a single context" do
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.set_container("knows", '@list')
      subject.serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
        }
      }, @debug)
    end

    it "@set with @id definition in a single context" do
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.set_container("knows", '@set')
      subject.serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@set"}
        }
      }, @debug)
    end

    it "@language with @id definition in a single context" do
      subject.set_mapping("name", RDF::FOAF.name)
      subject.set_language("name", 'en')
      subject.serialize.should produce({
        "@context" => {
          "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => "en"}
        }
      }, @debug)
    end

    it "@language with @id definition in a single context and equivalent default" do
      subject.set_mapping("name", RDF::FOAF.name)
      subject.default_language = 'en'
      subject.set_language("name", 'en')
      subject.serialize.should produce({
        "@context" => {
          "@language" => 'en',
          "name" => {"@id" => RDF::FOAF.name.to_s}
        }
      }, @debug)
    end

    it "@language with @id definition in a single context and different default" do
      subject.set_mapping("name", RDF::FOAF.name)
      subject.default_language = 'en'
      subject.set_language("name", 'de')
      subject.serialize.should produce({
        "@context" => {
          "@language" => 'en',
          "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => "de"}
        }
      }, @debug)
    end

    it "null @language with @id definition in a single context and default" do
      subject.set_mapping("name", RDF::FOAF.name)
      subject.default_language = 'en'
      subject.set_language("name", nil)
      subject.serialize.should produce({
        "@context" => {
          "@language" => 'en',
          "name" => {"@id" => RDF::FOAF.name.to_s, "@language" => nil}
        }
      }, @debug)
    end

    it "prefix with @type and @list" do
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.set_coerce("knows", "@id")
      subject.set_container("knows", '@list')
      subject.serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@type" => "@id", "@container" => "@list"}
        }
      }, @debug)
    end

    it "prefix with @type and @set" do
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.set_coerce("knows", "@id")
      subject.set_container("knows", '@set')
      subject.serialize.should produce({
        "@context" => {
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@type" => "@id", "@container" => "@set"}
        }
      }, @debug)
    end

    it "CURIE with @type" do
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.set_container("foaf:knows", '@list')
      subject.serialize.should produce({
        "@context" => {
          "foaf" => RDF::FOAF.to_uri,
          "foaf:knows" => {"@container" => "@list"}
        }
      }, @debug)
    end

    it "does not use aliased @id in key position" do
      subject.set_mapping("id", '@id')
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.set_container("knows", '@list')
      subject.serialize.should produce({
        "@context" => {
          "id" => "@id",
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
        }
      }, @debug)
    end

    it "does not use aliased @id in value position" do
      subject.set_mapping("id", "@id")
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.set_coerce("foaf:homepage", "@id")
      subject.serialize.should produce({
        "@context" => {
          "foaf" => RDF::FOAF.to_uri.to_s,
          "id" => "@id",
          "foaf:homepage" => {"@type" => "@id"}
        }
      }, @debug)
    end

    it "does not use aliased @type" do
      subject.set_mapping("type", "@type")
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.set_coerce("foaf:homepage", "@id")
      subject.serialize.should produce({
        "@context" => {
          "foaf" => RDF::FOAF.to_uri.to_s,
          "type" => "@type",
          "foaf:homepage" => {"@type" => "@id"}
        }
      }, @debug)
    end

    it "does not use aliased @container" do
      subject.set_mapping("container", '@container')
      subject.set_mapping("knows", RDF::FOAF.knows)
      subject.set_container("knows", '@list')
      subject.serialize.should produce({
        "@context" => {
          "container" => "@container",
          "knows" => {"@id" => RDF::FOAF.knows.to_s, "@container" => "@list"}
        }
      }, @debug)
    end

    it "compacts IRIs to CURIEs" do
      subject.set_mapping("ex", 'http://example.org/')
      subject.set_mapping("term", 'http://example.org/term')
      subject.set_coerce("term", "http://example.org/datatype")
      subject.serialize.should produce({
        "@context" => {
          "ex" => 'http://example.org/',
          "term" => {"@id" => "ex:term", "@type" => "ex:datatype"}
        }
      }, @debug)
    end

    context "extra keys or values" do
      {
        "extra key" => {
          :input => {"foo" => {"@id" => "http://example.com/foo", "@baz" => "foobar"}},
          :result => {"@context" => {"foo" => {"@id" => "http://example.com/foo", "@baz" => "foobar"}}}
        }
      }.each do |title, params|
        it title do
          ec = subject.parse(params[:input])
          ec.serialize.should produce(params[:result], @debug)
        end
      end
    end

  end

  describe "#expand_iri" do
    before(:each) do
      subject.set_mapping("ex", RDF::URI("http://example.org/"))
      subject.set_mapping("", RDF::URI("http://empty/"))
      subject.set_mapping("_", RDF::URI("http://underscore/"))
    end

    it "bnode" do
      subject.expand_iri("_:a").should be_a(RDF::Node)
    end

    context "relative IRI" do
      {
        :subject => true,
        :predicate => false,
        :object => true,
        :datatype => false
      }.each do |position, r|
        context "as #{position}" do
          {
            "absolute IRI" =>  ["http://example.org/", RDF::URI("http://example.org/"), true],
            "term" =>          ["ex",                  RDF::URI("http://example.org/"), true],
            "prefix:suffix" => ["ex:suffix",           RDF::URI("http://example.org/suffix"), true],
            "keyword" =>       ["@type",               "@type", true],
            "empty" =>         [":suffix",             RDF::URI("http://empty/suffix"), true],
            "unmapped" =>      ["foo",                 RDF::URI("foo"), false],
            "empty term" =>    ["",                    RDF::URI("http://empty/"), true],
            "another abs IRI"=>["ex://foo",            RDF::URI("ex://foo"), true],
            "absolute IRI looking like a curie" =>
                               ["foo:bar",             RDF::URI("foo:bar"), true],
            "bnode" =>         ["_:foo",               RDF::Node("foo"), true],
            "_" =>             ["_",                   RDF::URI("http://underscore/"), true],
          }.each do |title, (input,result,abs)|
            result = nil unless r || abs
            result = nil if title == 'unmapped'
            it title do
              subject.expand_iri(input).should produce(result, @debug)
            end
          end
        end
      end

      context "with base IRI" do
        {
          :subject => true,
          :predicate => false,
          :object => true,
          :datatype => false
        }.each do |position, r|
          context "as #{position}" do
            before(:each) do
              subject.instance_variable_set(:@base, RDF::URI("http://example.org/"))
              subject.mappings.delete("")
            end

            {
              "base" =>     ["",            RDF::URI("http://example.org/")],
              "relative" => ["a/b",         RDF::URI("http://example.org/a/b")],
              "hash" =>     ["#a",          RDF::URI("http://example.org/#a")],
              "absolute" => ["http://foo/", RDF::URI("http://foo/")]
            }.each do |title, (input,result)|
              result = nil unless r || title == 'absolute'
              it title do
                subject.expand_iri(input, :position => position).should produce(result, @debug)
              end
            end
          end
        end
      end
    end
  end

  describe "#compact_iri" do
    before(:each) do
      subject.set_mapping("ex", RDF::URI("http://example.org/"))
      subject.set_mapping("", RDF::URI("http://empty/"))
    end

    {
      "absolute IRI" =>  ["http://example.com/", RDF::URI("http://example.com/")],
      "term" =>          ["ex",                  RDF::URI("http://example.org/")],
      "prefix:suffix" => ["ex:suffix",           RDF::URI("http://example.org/suffix")],
      "keyword" =>       ["@type",               "@type"],
      "empty" =>         [":suffix",             RDF::URI("http://empty/suffix")],
      "unmapped" =>      ["foo",                 RDF::URI("foo")],
      "bnode" =>         ["_:a",                 RDF::Node("a")],
    }.each do |title, (result, input)|
      it title do
        subject.compact_iri(input).should produce(result, @debug)
      end
    end
    
    context "with value" do
      let(:ctx) do
        c = subject.parse({
          "xsd" => RDF::XSD.to_s,
          "plain" => "http://example.com/plain",
          "lang" => {"@id" => "http://example.com/lang", "@language" => "en"},
          "bool" => {"@id" => "http://example.com/bool", "@type" => "xsd:boolean"},
          "integer" => {"@id" => "http://example.com/integer", "@type" => "xsd:integer"},
          "double" => {"@id" => "http://example.com/double", "@type" => "xsd:double"},
          "date" => {"@id" => "http://example.com/date", "@type" => "xsd:date"},
          "id" => {"@id" => "http://example.com/id", "@type" => "@id"},
          "listplain" => {"@id" => "http://example.com/plain", "@container" => "@list"},
          "listlang" => {"@id" => "http://example.com/lang", "@language" => "en", "@container" => "@list"},
          "listbool" => {"@id" => "http://example.com/bool", "@type" => "xsd:boolean", "@container" => "@list"},
          "listinteger" => {"@id" => "http://example.com/integer", "@type" => "xsd:integer", "@container" => "@list"},
          "listdouble" => {"@id" => "http://example.com/double", "@type" => "xsd:double", "@container" => "@list"},
          "listdate" => {"@id" => "http://example.com/date", "@type" => "xsd:date", "@container" => "@list"},
          "listid" => {"@id" => "http://example.com/id", "@type" => "@id", "@container" => "@list"},
          "setplain" => {"@id" => "http://example.com/plain", "@container" => "@set"},
          "setlang" => {"@id" => "http://example.com/lang", "@language" => "en", "@container" => "@set"},
          "setbool" => {"@id" => "http://example.com/bool", "@type" => "xsd:boolean", "@container" => "@set"},
          "setinteger" => {"@id" => "http://example.com/integer", "@type" => "xsd:integer", "@container" => "@set"},
          "setdouble" => {"@id" => "http://example.com/double", "@type" => "xsd:double", "@container" => "@set"},
          "setdate" => {"@id" => "http://example.com/date", "@type" => "xsd:date", "@container" => "@set"},
          "setid" => {"@id" => "http://example.com/id", "@type" => "@id", "@container" => "@set"},
        })
        @debug.clear
        c
      end

      {
        "setplain"   => [
          "foo",
          {"@value" => "foo"},
          {"@value" => "de", "@language" => "de"},
          {"@value" => "other dt", "@language" => "http://example.com/other-datatype"}
        ],
        "setlang" => [{"@value" => "en", "@language" => "en"}],
        "setbool" => [true, false, {"@value" => "true", "@type" => RDF::XSD.boolean.to_s}],
        "setinteger" => [1, {"@value" => "1", "@type" => RDF::XSD.integer.to_s}],
        "setdouble" => [1.1, {"@value" => "1", "@type" => RDF::XSD.double.to_s}],
        "setdate" => [{"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}],
      }.each do |prop, values|
        context "uses #{prop}" do
          values.each do |value|
            it "for #{value.inspect}" do
              ctx.compact_iri("http://example.com/#{prop.sub('set', '')}", :value => value).should produce(prop, @debug)
            end
          end
        end
      end

      context "for @list" do
        {
          "listplain"   => [
            ["foo"],
            ["foo", "bar", 1],
            ["foo", "bar", 1.1],
            ["foo", "bar", true],
            [{"@value" => "foo"}, {"@value" => "bar"}, 1],
            [{"@value" => "de", "@language" => "de"}, {"@value" => "jp", "@language" => "jp"}],
          ],
          "listlang" => [[{"@value" => "en", "@language" => "en"}]],
          "listbool" => [[true], [false], [{"@value" => "true", "@type" => RDF::XSD.boolean.to_s}]],
          "listinteger" => [[1], [{"@value" => "1", "@type" => RDF::XSD.integer.to_s}]],
          "listdouble" => [[1.1], [{"@value" => "1", "@type" => RDF::XSD.double.to_s}]],
          "listdate" => [[{"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}]],
        }.each do |prop, values|
          context "uses #{prop}" do
            values.each do |value|
              it "for #{{"@list" => value}.inspect}" do
                ctx.compact_iri("http://example.com/#{prop.sub('list', '')}", :value => {"@list" => value}).should produce(prop, @debug)
              end
            end
          end
        end
      end
    end
  end

  describe "#term_rank" do
    {
      "no coercions" => {
        :defn => {},
        "boolean" => {:value => true, :rank => 2},
        "integer"    => {:value => 1, :rank => 2},
        "double" => {:value => 1.1, :rank => 2},
        "string" => {:value => "foo", :rank => 3},
        "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 1},
        "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 1},
        "id"    => {:value => {"@id" => "http://example/id"}, :rank => 1},
        "value string" => {:value => {"@value" => "foo"}, :rank => 3},
        "null"  => {:value => nil, :rank => 3},
      },
      "boolean" => {
        :defn => {"@type" => RDF::XSD.boolean.to_s},
        "boolean" => {:value => true, :rank => 3},
        "integer"    => {:value => 1, :rank => 2},
        "double" => {:value => 1.1, :rank => 2},
        "string" => {:value => "foo", :rank => 0},
        "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
        "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
        "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
        "value boolean" => {:value => {"@value" => "true", "@type" => RDF::XSD.boolean.to_s}, :rank => 3},
        "null"  => {:value => nil, :rank => 3},
      },
      "integer" => {
        :defn => {"@type" => RDF::XSD.integer.to_s},
        "boolean" => {:value => true, :rank => 2},
        "integer"    => {:value => 1, :rank => 3},
        "double" => {:value => 1.1, :rank => 2},
        "string" => {:value => "foo", :rank => 0},
        "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
        "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
        "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
        "value integer" => {:value => {"@value" => "1", "@type" => RDF::XSD.integer.to_s}, :rank => 3},
        "null"  => {:value => nil, :rank => 3},
      },
      "double" => {
        :defn => {"@type" => RDF::XSD.double.to_s},
        "boolean" => {:value => true, :rank => 2},
        "integer"    => {:value => 1, :rank => 2},
        "double" => {:value => 1.1, :rank => 3},
        "string" => {:value => "foo", :rank => 0},
        "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
        "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
        "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
        "value double" => {:value => {"@value" => "1.1", "@type" => RDF::XSD.double.to_s}, :rank => 3},
        "null"  => {:value => nil, :rank => 3},
      },
      "date" => {
        :defn => {"@type" => RDF::XSD.date.to_s},
        "boolean" => {:value => true, :rank => 2},
        "integer"    => {:value => 1, :rank => 2},
        "double" => {:value => 1.1, :rank => 2},
        "string" => {:value => "foo", :rank => 0},
        "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 3},
        "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
        "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
        "null"  => {:value => nil, :rank => 3},
      },
      "lang" => {
        :defn => {"@language" => "en"},
        "boolean" => {:value => true, :rank => 2},
        "integer"    => {:value => 1, :rank => 2},
        "double" => {:value => 1.1, :rank => 2},
        "string" => {:value => "foo", :rank => 0},
        "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
        "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 3},
        "other lang" => {:value => {"@value" => "apple", "@language" => "de"}, :rank => 0},
        "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
        "null"  => {:value => nil, :rank => 3},
      },
      "id" => {
        :defn => {"@type" => "@id"},
        "boolean" => {:value => true, :rank => 2},
        "integer"    => {:value => 1, :rank => 2},
        "double" => {:value => 1.1, :rank => 2},
        "string" => {:value => "foo", :rank => 0},
        "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
        "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
        "other lang" => {:value => {"@value" => "apple", "@language" => "de"}, :rank => 0},
        "id"    => {:value => {"@id" => "http://example/id"}, :rank => 3},
        "null"  => {:value => nil, :rank => 3},
      },
    }.each do |title, properties|
      context title do
        let(:ctx) do
          subject.parse({
            "term" => properties[:defn].merge("@id" => "http://example.org/term")
          })
        end
        properties.each do |type, defn|
          next unless type.is_a?(String)
          it "returns #{defn[:rank]} for #{type}" do
            ctx.send(:term_rank, "term", defn[:value]).should produce(defn[:rank], @debug)
          end
        end
      end
    end
    
    context "with default language" do
      before(:each) {subject.default_language = "en"}
      {
        "no coercions" => {
          :defn => {},
          "boolean" => {:value => true, :rank => 2},
          "integer"    => {:value => 1, :rank => 2},
          "double" => {:value => 1.1, :rank => 2},
          "string" => {:value => "foo", :rank => 0},
          "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 1},
          "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 3},
          "id"    => {:value => {"@id" => "http://example/id"}, :rank => 1},
          "value string" => {:value => {"@value" => "foo"}, :rank => 3},
          "null"  => {:value => nil, :rank => 3},
        },
        "boolean" => {
          :defn => {"@type" => RDF::XSD.boolean.to_s},
          "boolean" => {:value => true, :rank => 3},
          "integer"    => {:value => 1, :rank => 2},
          "double" => {:value => 1.1, :rank => 2},
          "string" => {:value => "foo", :rank => 0},
          "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
          "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
          "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
          "value boolean" => {:value => {"@value" => "true", "@type" => RDF::XSD.boolean.to_s}, :rank => 3},
          "null"  => {:value => nil, :rank => 3},
        },
        "integer" => {
          :defn => {"@type" => RDF::XSD.integer.to_s},
          "boolean" => {:value => true, :rank => 2},
          "integer"    => {:value => 1, :rank => 3},
          "double" => {:value => 1.1, :rank => 2},
          "string" => {:value => "foo", :rank => 0},
          "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
          "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
          "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
          "value integer" => {:value => {"@value" => "1", "@type" => RDF::XSD.integer.to_s}, :rank => 3},
          "null"  => {:value => nil, :rank => 3},
        },
        "double" => {
          :defn => {"@type" => RDF::XSD.double.to_s},
          "boolean" => {:value => true, :rank => 2},
          "integer"    => {:value => 1, :rank => 2},
          "double" => {:value => 1.1, :rank => 3},
          "string" => {:value => "foo", :rank => 0},
          "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
          "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
          "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
          "value double" => {:value => {"@value" => "1.1", "@type" => RDF::XSD.double.to_s}, :rank => 3},
          "null"  => {:value => nil, :rank => 3},
        },
        "date" => {
          :defn => {"@type" => RDF::XSD.date.to_s},
          "boolean" => {:value => true, :rank => 2},
          "integer"    => {:value => 1, :rank => 2},
          "double" => {:value => 1.1, :rank => 2},
          "string" => {:value => "foo", :rank => 0},
          "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 3},
          "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
          "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
          "null"  => {:value => nil, :rank => 3},
        },
        "lang" => {
          :defn => {"@language" => "en"},
          "boolean" => {:value => true, :rank => 2},
          "integer"    => {:value => 1, :rank => 2},
          "double" => {:value => 1.1, :rank => 2},
          "string" => {:value => "foo", :rank => 0},
          "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
          "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 3},
          "other lang" => {:value => {"@value" => "apple", "@language" => "de"}, :rank => 0},
          "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
          "null"  => {:value => nil, :rank => 3},
        },
        "null lang" => {
          :defn => {"@language" => nil},
          "boolean" => {:value => true, :rank => 2},
          "integer"    => {:value => 1, :rank => 2},
          "double" => {:value => 1.1, :rank => 2},
          "string" => {:value => "foo", :rank => 3},
          "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
          "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
          "id"    => {:value => {"@id" => "http://example/id"}, :rank => 0},
          "null"  => {:value => nil, :rank => 3},
        },
        "id" => {
          :defn => {"@type" => "@id"},
          "boolean" => {:value => true, :rank => 2},
          "integer"    => {:value => 1, :rank => 2},
          "double" => {:value => 1.1, :rank => 2},
          "string" => {:value => "foo", :rank => 0},
          "date"  => {:value => {"@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s}, :rank => 0},
          "lang"  => {:value => {"@value" => "apple", "@language" => "en"}, :rank => 0},
          "other lang" => {:value => {"@value" => "apple", "@language" => "de"}, :rank => 0},
          "id"    => {:value => {"@id" => "http://example/id"}, :rank => 3},
          "null"  => {:value => nil, :rank => 3},
        },
      }.each do |title, properties|
        context title do
          let(:ctx) do
            subject.parse({
              "term" => properties[:defn].merge("@id" => "http://example.org/term")
            })
          end
          properties.each do |type, defn|
            next unless type.is_a?(String)
            it "returns #{defn[:rank]} for #{type}" do
              ctx.send(:term_rank, "term", defn[:value]).should produce(defn[:rank], @debug)
            end
          end
        end
      end
    end
  end

  describe "#expand_value" do
    before(:each) do
      subject.set_mapping("dc", RDF::DC.to_uri)
      subject.set_mapping("ex", RDF::URI("http://example.org/"))
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.set_mapping("xsd", RDF::XSD.to_uri)
      subject.set_coerce("foaf:age", RDF::XSD.integer)
      subject.set_coerce("foaf:knows", "@id")
      subject.set_coerce("dc:created", RDF::XSD.date)
      subject.set_coerce("ex:double", RDF::XSD.double)
      subject.set_coerce("ex:boolean", RDF::XSD.boolean)
    end

    {
      "absolute IRI" =>   ["foaf:knows",  "http://example.com/",  {"@id" => "http://example.com/"}],
      "term" =>           ["foaf:knows",  "ex",                   {"@id" => "http://example.org/"}],
      "prefix:suffix" =>  ["foaf:knows",  "ex:suffix",            {"@id" => "http://example.org/suffix"}],
      "no IRI" =>         ["foo",         "http://example.com/",  "http://example.com/"],
      "no term" =>        ["foo",         "ex",                   "ex"],
      "no prefix" =>      ["foo",         "ex:suffix",            "ex:suffix"],
      "integer" =>        ["foaf:age",    "54",                   {"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
      "date " =>          ["dc:created",  "2011-12-27Z",          {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "native boolean" => ["foo", true,                           true],
      "native integer" => ["foo", 1,                              1],
      "native double" =>  ["foo", 1.1e1,                          1.1E1],
      "native date" =>    ["foo", Date.parse("2011-12-27Z"),      {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "native time" =>    ["foo", Time.parse("10:11:12Z"),        {"@value" => "10:11:12Z", "@type" => RDF::XSD.time.to_s}],
      "native dateTime" =>["foo", DateTime.parse("2011-12-27T10:11:12Z"), {"@value" => "2011-12-27T10:11:12Z", "@type" => RDF::XSD.dateTime.to_s}],
      "rdf boolean" =>    ["foo", RDF::Literal(true),             true],
      "rdf integer" =>    ["foo", RDF::Literal(1),                1],
      "rdf decimal" =>    ["foo", RDF::Literal::Decimal.new(1.1), {"@value" => "1.1", "@type" => RDF::XSD.decimal.to_s}],
      "rdf double" =>     ["foo", RDF::Literal::Double.new(1.1),  1.1],
      "rdf URI" =>        ["foo", RDF::URI("foo"),                {"@id" => "foo"}],
      "rdf date " =>      ["foo", RDF::Literal(Date.parse("2011-12-27Z")), {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
    }.each do |title, (key, compacted, expanded)|
      it title do
        subject.expand_value(key, compacted).should produce(expanded, @debug)
      end
    end

    context "@language" do
      before(:each) {subject.default_language = "en"}
      {
        "no IRI" =>         ["foo",         "http://example.com/",  {"@value" => "http://example.com/", "@language" => "en"}],
        "no term" =>        ["foo",         "ex",                   {"@value" => "ex", "@language" => "en"}],
        "no prefix" =>      ["foo",         "ex:suffix",            {"@value" => "ex:suffix", "@language" => "en"}],
        "native boolean" => ["foo",         true,                   true],
        "native integer" => ["foo",         1,                      1],
        "native double" =>  ["foo",         1.1,                    1.1],
      }.each do |title, (key, compacted, expanded)|
        it title do
          subject.expand_value(key, compacted).should produce(expanded, @debug)
        end
      end
    end
    
    context "coercion" do
      before(:each) {subject.default_language = "en"}
      {
        "boolean-boolean" => ["ex:boolean", true,   true],
        "boolean-double"  => ["ex:double",  true,   {"@value" => "true", "@type" => RDF::XSD.double.to_s}],
        "boolean-int"     => ["foaf:age",   true,   true],
        "double-boolean"  => ["ex:boolean", 1.1,    {"@value" => "1.1", "@type" => RDF::XSD.boolean.to_s}],
        "double-double"   => ["ex:double",  1.1,    {"@value" => "1.1E0", "@type" => RDF::XSD.double.to_s}],
        "double-int"      => ["foaf:age",   1.1,    {"@value" => "1", "@type" => RDF::XSD.integer.to_s}],
        "int-boolean"     => ["ex:boolean", 1,      {"@value" => "1", "@type" => RDF::XSD.boolean.to_s}],
        "int-double"      => ["ex:double",  1,      {"@value" => "1.0E0", "@type" => RDF::XSD.double.to_s}],
        "int-int"         => ["foaf:age",   1,      1],
        "string-boolean"  => ["ex:boolean", "foo",  {"@value" => "foo", "@type" => RDF::XSD.boolean.to_s}],
        "string-double"   => ["ex:double",  "foo",  {"@value" => "foo", "@type" => RDF::XSD.double.to_s}],
        "string-int"      => ["foaf:age",   "foo",  {"@value" => "foo", "@type" => RDF::XSD.integer.to_s}],
      }.each do |title, (key, compacted, expanded)|
        it title do
          subject.expand_value(key, compacted).should produce(expanded, @debug)
        end
      end
    end
  end

  describe "compact_value" do
    before(:each) do
      subject.set_mapping("dc", RDF::DC.to_uri)
      subject.set_mapping("ex", RDF::URI("http://example.org/"))
      subject.set_mapping("foaf", RDF::FOAF.to_uri)
      subject.set_mapping("xsd", RDF::XSD.to_uri)
      subject.set_coerce("foaf:age", RDF::XSD.integer)
      subject.set_coerce("foaf:knows", "@id")
      subject.set_coerce("dc:created", RDF::XSD.date)
    end

    {
      "absolute IRI" =>   ["foaf:knows",  "http://example.com/",  {"@id" => "http://example.com/"}],
      "term" =>           ["foaf:knows",  "ex",                   {"@id" => "http://example.org/"}],
      "prefix:suffix" =>  ["foaf:knows",  "ex:suffix",            {"@id" => "http://example.org/suffix"}],
      "integer" =>        ["foaf:age",    54,                     {"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
      "date " =>          ["dc:created",  "2011-12-27Z",          {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "no IRI" =>         ["foo", {"@id" => "http://example.com/"},  {"@id" => "http://example.com/"}],
      "no IRI (term)" =>  ["foo", {"@id" => "ex"},                {"@id" => "http://example.org/"}],
      "no IRI (CURIE)" => ["foo", {"@id" => "foaf:Person"},       {"@id" => RDF::FOAF.Person.to_s}],
      "no boolean" =>     ["foo", true,                           {"@value" => "true", "@type" => RDF::XSD.boolean.to_s}],
      "no integer" =>     ["foo", 54,                             {"@value" => "54", "@type" => RDF::XSD.integer.to_s}],
      "no date " =>       ["foo", {"@value" => "2011-12-27Z", "@type" => "xsd:date"}, {"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
      "no string " =>     ["foo", "string",                       {"@value" => "string"}],
    }.each do |title, (key, compacted, expanded)|
      it title do
        subject.compact_value(key, expanded).should produce(compacted, @debug)
      end
    end

    context "@language" do
      {
        "@id"                            => ["foo", {"@id" => "foo"},                                   {"@id" => "foo"}],
        "integer"                        => ["foo", 54,                                                 {"@value" => "54", "@type" => "xsd:integer"}],
        "date"                           => ["foo", {"@value" => "2011-12-27Z","@type" => "xsd:date"},{"@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s}],
        "no lang"                        => ["foo", {"@value" => "foo"  },                            {"@value" => "foo"}],
        "same lang"                      => ["foo", "foo",                                              {"@value" => "foo", "@language" => "en"}],
        "other lang"                     => ["foo",  {"@value" => "foo", "@language" => "bar"},       {"@value" => "foo", "@language" => "bar"}],
        "no lang with @type coercion"    => ["dc:created", {"@value" => "foo"},                       {"@value" => "foo"}],
        "no lang with @id coercion"      => ["foaf:knows", {"@value" => "foo"},                       {"@value" => "foo"}],
        "same lang with @type coercion"  => ["dc:created", {"@value" => "foo"},                       {"@value" => "foo"}],
        "same lang with @id coercion"    => ["foaf:knows", {"@value" => "foo"},                       {"@value" => "foo"}],
        "other lang with @type coercion" => ["dc:created", {"@value" => "foo", "@language" => "bar"}, {"@value" => "foo", "@language" => "bar"}],
        "other lang with @id coercion"   => ["foaf:knows", {"@value" => "foo", "@language" => "bar"}, {"@value" => "foo", "@language" => "bar"}],
      }.each do |title, (key, compacted, expanded)|
        it title do
          subject.default_language = "en"
          subject.compact_value(key, expanded).should produce(compacted, @debug)
        end
      end
    end

    [[], true, false, 1, 1.1, "string"].each do |v|
      it "raises error given #{v.class}" do
        lambda {subject.compact_value("foo", v)}.should raise_error(JSON::LD::ProcessingError::Lossy)
      end
    end

    context "keywords" do
      before(:each) do
        subject.set_mapping("id", "@id")
        subject.set_mapping("type", "@type")
        subject.set_mapping("list", "@list")
        subject.set_mapping("set", "@set")
        subject.set_mapping("language", "@language")
        subject.set_mapping("literal", "@value")
      end

      {
        "@id" =>      [{"id" => "http://example.com/"},             {"@id" => "http://example.com/"}],
        "@type" =>    [{"literal" => "foo", "type" => "http://example.com/"},
                                                                    {"@value" => "foo", "@type" => "http://example.com/"}],
        "@value" =>   [{"literal" => "foo", "language" => "bar"},   {"@value" => "foo", "@language" => "bar"}],
        "@list" =>    [{"list" => ["foo"]},                         {"@list" => ["foo"]  }],
        "@set" =>     [{"set" => ["foo"]},                         {"@set" => ["foo"]  }],
      }.each do |title, (compacted, expanded)|
        it title do
          subject.compact_value("foo", expanded).should produce(compacted, @debug)
        end
      end
    end
  end
end
