# coding: utf-8
require_relative 'spec_helper'

describe JSON::LD do
  describe "test suite" do
    require_relative 'suite_helper'
    m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}toRdf-manifest.jsonld")
    describe m.name do
      m.entries.each do |t|
        specify "#{t.property('@id')}: #{t.name}#{' (negative test)' unless t.positiveTest?}" do
          skip "Native value fidelity" if %w(toRdf/0035-in.jsonld).include?(t.property('input'))
          pending "Generalized RDF" if %w(toRdf/0118-in.jsonld toRdf/e075-in.jsonld).include?(t.property('input'))
          pending "Non-heirarchical IRI joining" if %w(toRdf/0130-in.jsonld).include?(t.property('input'))
          if %w(#t0118).include?(t.property('@id'))
            expect {t.run self}.to write(/Statement .* is invalid/).to(:error)
          elsif %w(#te068).include?(t.property('@id'))
            expect {t.run self}.to write("[DEPRECATION]").to(:error)
          else
            t.run self
          end
        end
      end
    end
  end
end unless ENV['CI']