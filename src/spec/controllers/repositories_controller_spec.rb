#
# Copyright 2012 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

require 'spec_helper'


describe RepositoriesController, :katello => true do
  include LoginHelperMethods
  include LocaleHelperMethods
  include OrganizationHelperMethods
  include ProductHelperMethods
  include RepositoryHelperMethods
  include OrchestrationHelper
  include AuthorizationHelperMethods

  describe "rules" do
    before do
      disable_product_orchestration
      disable_user_orchestration

      @organization = new_test_org
      @provider = Provider.create!(:provider_type=>Provider::CUSTOM, :name=>"foo1", :organization=>@organization)
      Provider.stub!(:find).and_return(@provider)
      @product = Product.new({:name=>"prod", :label=> "prod"})

      @product.provider = @provider
      @product.environments << @organization.library
      @product.stub(:arch).and_return('noarch')
      @product.save!
      Product.stub!(:find).and_return(@product)
      @repository = MemoStruct.new(:id =>1222)
    end

    describe "GET New" do
      let(:action) {:new}
      let(:req) { get :new, :provider_id => @provider.id, :product_id => @product.id}
      let(:authorized_user) do
        user_with_permissions { |u| u.can(:update, :providers,@provider.id, @organization) }
      end
      let(:unauthorized_user) do
        user_without_permissions
      end
      it_should_behave_like "protected action"
    end

    describe "GET Edit" do
      before do
        Product.stub!(:find).and_return(@product)
        Runcible::Extensions::Repository.stub(:find).and_return(@repository)
      end
      let(:action) {:edit}
      let(:req) { get :edit, :provider_id => @provider.id, :product_id => @product.id, :id => @repository.id}
      let(:authorized_user) do
        user_with_permissions { |u| u.can(:read, :providers,@provider.id, @organization) }
      end
      let(:unauthorized_user) do
        user_without_permissions
      end
      it_should_behave_like "protected action"
    end
  end

  describe "other-tests" do
    before (:each) do
      login_user
      set_default_locale

      @org = new_test_org
      @product = new_test_product(@org, @org.library)
      @gpg = GpgKey.create!(:name => "foo", :organization => @organization, :content => "222")
      @ep = EnvironmentProduct.find_or_create(@organization.library, @product)
      controller.stub!(:current_organization).and_return(@org)
      Resources::Candlepin::Content.stub(:create => {:id => "123"})
    end
    let(:invalidrepo) do
      {
        :product_id => @product.id,
        :provider_id => @product.provider.id,
        :repo => {
          :name => 'test',
          :feed => 'www.foo.com'
        }
      }
    end

    describe "Create a Repo" do
      it "should reject invalid urls" do
        controller.should notify.error
        post :create, invalidrepo
        response.should_not be_success
      end
    end

    context "Test gpg create" do
      before do
        disable_product_orchestration
        content = { :name => "FOO",
                    :id=>"12345",
                    :contentUrl => '/some/path',
                    :gpgUrl => nil,
                    :type => "yum",
                    :label => 'label',
                    :vendor => Provider::CUSTOM}

        Resources::Candlepin::Content.stub!(:get).and_return(content)
        Resources::Candlepin::Content.stub!(:create).and_return(content)

        @repo_name = "repo-#{rand 10 ** 8}"
        post :create, { :product_id => @product.id,
                        :provider_id => @product.provider.id,
                        :repo => {:name => @repo_name,
                              :label => @repo_name,
                              :feed => "http://foo.com",
                              :gpg_key =>@gpg.id.to_s}}
      end
      specify  do
        response.should be_success
      end
      subject {Repository.find_by_name(@repo_name)}
      it{should_not be_nil}
      its(:gpg_key){should == @gpg}
    end

    context "Test update gpg" do
      before do
        disable_product_orchestration
        content = { :name => "FOO",
                    :id=>"12345",
                    :contentUrl => '/some/path',
                    :gpgUrl => nil,
                    :type => "yum",
                    :label => 'label',
                    :vendor => Provider::CUSTOM}

        Resources::Candlepin::Content.stub!(:get).and_return(content)
        Resources::Candlepin::Content.stub!(:create).and_return(content)

        @repo = new_test_repo(@ep, "newname#{rand 10**6}", "http://fedorahosted org")
        product = @repo.product
        Repository.stub(:find).and_return(@repo)
        @repo.stub(:content).and_return(OpenStruct.new(:gpgUrl=>""))
        @repo.should_receive(:update_content).and_return(Candlepin::Content.new)
        #@repo.stub(:product).and_return(product)

        put :update_gpg_key, { :product_id => @product.id,
                              :provider_id => @product.provider.id,
                                :id => @repo.id,
                                :gpg_key => @gpg.id.to_s}
      end

      specify do
        response.should be_success
      end

      subject {Repository.find(@repo.id)}
      it{should_not be_nil}
      its(:gpg_key){should == @gpg}
    end
  end
end
