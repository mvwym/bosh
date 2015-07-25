require 'spec_helper'

describe Bosh::Director::DeploymentPlan::Stemcell do
  def make(spec)
    BD::DeploymentPlan::Stemcell.new(spec)
  end

  def make_plan(deployment = nil)
    instance_double('Bosh::Director::DeploymentPlan::Planner', :model => deployment)
  end

  def make_deployment(name)
    BD::Models::Deployment.make(:name => name)
  end

  def make_stemcell(name, version)
    BD::Models::Stemcell.make(:name => name, :version => version)
  end

  let(:valid_spec) do
    {
      "name" => "stemcell-name",
      "version" => "0.5.2"
    }
  end

  describe "creating" do
    it "parses name and version" do
      sc = make(valid_spec)
      expect(sc.name).to eq("stemcell-name")
      expect(sc.version).to eq("0.5.2")
    end

    it "requires name and version" do
      %w(name version).each do |key|
        spec = valid_spec.dup
        spec.delete(key)

        expect {
          make(spec)
        }.to raise_error(BD::ValidationMissingField)
      end
    end
  end

  it "returns stemcell spec as Hash" do
    sc = make(valid_spec)
    expect(sc.spec).to eq(valid_spec)
  end

  describe "binding stemcell model" do
    it "should bind stemcell model" do
      deployment = make_deployment("mycloud")
      plan = make_plan(deployment)
      stemcell = make_stemcell("stemcell-name", "0.5.2")

      sc = make(valid_spec)
      sc.bind_model(plan)

      expect(sc.model).to eq(stemcell)
      expect(stemcell.deployments).to eq([deployment])
    end

    it "should fail if stemcell doesn't exist" do
      deployment = make_deployment("mycloud")
      plan = make_plan(deployment)

      sc = make(valid_spec)
      expect {
        sc.bind_model(plan)
      }.to raise_error(BD::StemcellNotFound)
    end

    it "binds stemcells to the deployment DB" do
      deployment = make_deployment("mycloud")
      plan = make_plan(deployment)

      sc1 = make_stemcell("foo", "42-dev")
      sc2 = make_stemcell("bar", "55-dev")

      spec1 = {"name" => "foo", "version" => "42-dev"}
      spec2 = {"name" => "bar", "version" => "55-dev"}

      make(spec1).bind_model(plan)
      make(spec2).bind_model(plan)

      expect(deployment.stemcells).to match_array([sc1, sc2])
    end

    it "doesn't bind model if deployment plan has unbound deployment" do
      plan = make_plan(nil)
      expect {
        sc = make({"name" => "foo", "version" => "42"})
        sc.bind_model(plan)
      }.to raise_error(BD::DirectorError,
                       "Deployment not bound in the deployment plan")
    end
  end
end
