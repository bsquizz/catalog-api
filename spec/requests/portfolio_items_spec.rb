describe "PortfolioItemRequests", :type => :request do
  around do |example|
    bypass_rbac do
      example.call
    end
  end

  let(:service_offering_ref) { "998" }
  let(:service_offering_source_ref) { "568" }
  let(:tenant) { create(:tenant) }
  let(:order) { create(:order, :tenant_id => tenant.id) }
  let!(:portfolio) { create(:portfolio, :tenant_id => tenant.id) }
  let!(:portfolio_items) { portfolio.portfolio_items << portfolio_item }
  let(:portfolio_id) { portfolio.id }
  let(:portfolio_item) do
    create(:portfolio_item, :service_offering_ref        => service_offering_ref,
                            :service_offering_source_ref => service_offering_source_ref,
                            :tenant_id                   => tenant.id)
  end
  let(:portfolio_item_id)    { portfolio_item.id }
  let(:topo_ex)              { Catalog::TopologyError.new("kaboom") }

  describe "GET /portfolio_items/:portfolio_item_id" do
    before do
      get "#{api}/portfolio_items/#{portfolio_item_id}", :headers => default_headers
    end

    context 'the portfolio_item exists' do
      it 'returns status code 200' do
        expect(response).to have_http_status(200)
      end

      it 'returns the portfolio_item we asked for' do
        expect(json["id"]).to eq portfolio_item.id.to_s
      end
    end

    context 'the portfolio_item does not exist' do
      let(:portfolio_item_id) { 0 }

      it "can't be requested" do
        expect(response).to have_http_status(404)
      end
    end
  end

  describe "GET /portfolios/:portfolio_id/portfolio_items" do
    before do
      get "#{api}/portfolios/#{portfolio_id}/portfolio_items", :headers => default_headers
    end

    context "when the portfolio exists" do
      it 'returns all associated portfolio_items' do
        expect(json).not_to be_empty
        expect(json['meta']['count']).to eq 1
        portfolio_item_ids = portfolio_items.map { |x| x.id.to_s }.sort
        expect(json['data'].map { |x| x['id'] }.sort).to eq portfolio_item_ids
      end
    end

    context "when the portfolio does not exist" do
      let(:portfolio_id) { portfolio.id + 100 }

      it 'returns a 404' do
        expect(json["message"]).to eq("Not Found")
        expect(response.status).to eq(404)
      end
    end
  end

  describe "POST /portfolios/:portfolio_id/portfolio_items" do
    let(:params) { {:portfolio_item_id => portfolio_item.id} }
    before do
      post "#{api}/portfolios/#{portfolio.id}/portfolio_items", :params => params, :headers => default_headers
    end

    it 'returns a 200' do
      expect(response).to have_http_status(200)
    end

    it 'returns the portfolio_item which now points back to the portfolio' do
      expect(json.size).to eq 1
      expect(json.first['portfolio_id']).to eq portfolio.id.to_s
    end
  end

  describe 'DELETE admin tagged /portfolio_items/:portfolio_item_id' do
    # TODO: https://github.com/ManageIQ/catalog-api/issues/85
    let(:valid_attributes) { { :name => 'PatchPortfolio', :description => 'description for patched portfolio' } }

    context 'when v1.0 :portfolio_item_id is valid' do
      before do
        delete "#{api}/portfolio_items/#{portfolio_item_id}", :headers => default_headers, :params => valid_attributes
      end

      it 'discards the record' do
        expect(response).to have_http_status(204)
      end

      it 'is still present in the db, just with deleted_at set' do
        expect(PortfolioItem.with_discarded.find_by(:id => portfolio_item_id).discarded_at).to_not be_nil
      end

    end
  end

  describe 'GET portfolio items' do
    context "v1.0" do
      it "success" do
        portfolio_item
        get "/#{api}/portfolio_items", :headers => default_headers
        expect(response).to have_http_status(200)
        expect(JSON.parse(response.body)['data'].count).to eq(1)
      end
    end
  end

  context "when adding portfolio items" do
    let(:add_to_portfolio_svc) { double(ServiceOffering::AddToPortfolioItem) }
    let(:params) { { :service_offering_ref => service_offering_ref } }
    let(:permitted_params) { ActionController::Parameters.new(params).permit(:service_offering_ref) }

    before do
      allow(ServiceOffering::AddToPortfolioItem).to receive(:new).with(permitted_params).and_return(add_to_portfolio_svc)
    end

    it "returns not found when topology doesn't have the service_offering_ref" do
      allow(add_to_portfolio_svc).to receive(:process).and_raise(topo_ex)

      post "#{api}/portfolio_items", :params => params, :headers => default_headers
      expect(response).to have_http_status(:not_found)
    end

    it "returns the new portfolio item when topology has the service_offering_ref" do
      allow(add_to_portfolio_svc).to receive(:process).and_return(add_to_portfolio_svc)
      allow(add_to_portfolio_svc).to receive(:item).and_return(portfolio_item)

      post "#{api}/portfolio_items", :params => params, :headers => default_headers
      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq portfolio_item.id.to_s
      expect(json["service_offering_ref"]).to eq service_offering_ref
    end
  end

  context "service plans" do
    let(:svc_object)           { instance_double("Catalog::ServicePlans") }
    let(:plans)                { [{}, {}] }

    before do
      allow(Catalog::ServicePlans).to receive(:new).with(portfolio_item.id.to_s).and_return(svc_object)
    end

    it "fetches plans" do
      allow(svc_object).to receive(:process).and_return(svc_object)
      allow(svc_object).to receive(:items).and_return(plans)

      get "/#{api}/portfolio_items/#{portfolio_item.id}/service_plans", :headers => default_headers

      expect(JSON.parse(response.body).count).to eq(2)
      expect(response.content_type).to eq("application/json")
      expect(response).to have_http_status(:ok)
    end

    it "raises error" do
      allow(svc_object).to receive(:process).and_raise(topo_ex)

      get "/#{api}/portfolio_items/#{portfolio_item.id}/service_plans", :headers => default_headers
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  context "v1.0 provider control parameters" do
    let(:svc_object)  { instance_double("Catalog::ProviderControlParameters") }
    let(:url)         { "#{api}/portfolio_items/#{portfolio_item.id}/provider_control_parameters" }

    before do
      allow(Catalog::ProviderControlParameters).to receive(:new).with(portfolio_item.id.to_s).and_return(svc_object)
    end

    it "fetches plans" do
      allow(svc_object).to receive(:process).and_return(svc_object)
      allow(svc_object).to receive(:data).and_return(:fred => 'bedrock')

      get url, :headers => default_headers

      expect(response.content_type).to eq("application/json")
      expect(response).to have_http_status(:ok)
    end

    it "raises error" do
      allow(svc_object).to receive(:process).and_raise(topo_ex)

      get url, :headers => default_headers

      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "patching portfolio items" do
    let(:valid_attributes) { { :name => 'PatchPortfolio', :description => 'PatchDescription', :workflow_ref => 'PatchWorkflowRef'} }
    let(:invalid_attributes) { { :name => 'PatchPortfolio', :service_offering_ref => "27" } }

    context "when passing in valid attributes" do
      before do
        patch "#{api}/portfolio_items/#{portfolio_item.id}", :params => valid_attributes, :headers => default_headers
      end

      it 'returns a 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'patches the record' do
        expect(json).to include(valid_attributes.stringify_keys)
      end
    end

    context "when passing in read-only attributes" do
      before do
        patch "#{api}/portfolio_items/#{portfolio_item.id}", :params => invalid_attributes, :headers => default_headers
      end

      it 'returns a 200' do
        expect(response).to have_http_status(:ok)
      end

      it 'updates the field that is allowed' do
        expect(json["name"]).to eq invalid_attributes[:name]
      end

      it "does not update the read-only field" do
        expect(json["service_offering_ref"]).to_not eq invalid_attributes[:service_offering_ref]
      end
    end
  end
end
