# -*- coding: utf-8 -*-
#
# Copyright 2011 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

class SystemsController < ApplicationController
  include SystemsHelper

  before_filter :find_system, :except =>[:index, :items, :environments, :bulk_destroy, :destroy, :new, :create]
  before_filter :find_systems, :only=>[:bulk_destroy]

  before_filter :find_environment, :only => [:environments, :new]
  before_filter :authorize

  before_filter :setup_options, :only => [:index, :items, :environments]

  # two pane columns and mapping for sortable fields
  COLUMNS = {'name' => 'name_sort', 'lastCheckin' => 'lastCheckin'}

  def rules
    edit_system = lambda{System.find(params[:id]).editable?}
    read_system = lambda{System.find(params[:id]).readable?}
    env_system = lambda{@environment.systems_readable?}
    any_readable = lambda{System.any_readable?(current_organization)}
    delete_systems = lambda{true}
    register_system = lambda { System.registerable?(@environment, current_organization) }
    items_test = lambda do
      if params[:env_id]
        @environment = KTEnvironment.find(params[:env_id])
        @environment && @environment.systems_readable?
      else
        System.any_readable?(current_organization)
      end
    end
    {
      :index => any_readable,
      :create => register_system,
      :new => register_system,
      :items => items_test,
      :environments => env_system,
      :subscriptions => read_system,
      :update_subscriptions => edit_system,
      :products => read_system,
      :more_products => read_system,
      :update => edit_system,
      :edit => read_system,
      :show => read_system,
      :facts => read_system,
      :destroy=> delete_systems,
      :bulk_destroy => delete_systems
    }
  end

  def new
    @system = System.new
    @system.facts = {} #this is nil to begin with
    @organization = current_organization
    accessible_envs = current_organization.environments
    setup_environment_selector(current_organization, accessible_envs)

    # This controls whether the New System page will display an environment selector or not.
    # Since only one selector may exist at a time, it is left off of the New page when the
    # Environments page is displayed.
    envsys = !params[:env_id].nil?

    render :partial=>"new", :layout => "tupane_layout", :locals=>{:system=>@system, :accessible_envs => accessible_envs, :envsys => envsys}
  end

  def create
    begin
      #{"method"=>"post", "system"=>{"name"=>"asdfsdf", "sockets"=>"asdfasdf", "arch"=>"asdfasdfasdf", "virtualized"=>"asdfasd"}, "authenticity_token"=>"n7hXf3d+YZZnvxqcjhQjPaD»
      @system = System.new
      @system.facts = {}
      @system.arch = params["arch"]["arch_id"]
      @system.sockets = params["system"]["sockets"]
      @system.guest = (params["system_type"]["virtualized"] == 'virtual')
      @system.name= params["system"]["name"]
      @system.cp_type = "system"
      @system.environment = KTEnvironment.find(params["system"]["environment_id"])
      #create it in candlepin, parse the JSON and create a new ruby object to pass to the view
      saved = @system.save!
      #find the newly created system
      if saved
        notice _("System '#{@system['name']}' was created.")

        if search_validate(System, @system.id, params[:search])
          render :partial=>"systems/list_systems",
            :locals=>{:accessor=>"id", :columns=>['name', 'lastCheckin','created' ], :collection=>[@system], :name=> controller_display_name}
        else
          notice _("'#{@system["name"]}' did not meet the current search criteria and is not being shown."), { :level => 'message', :synchronous_request => false }
          render :json => { :no_match => true }
        end
      end

    rescue Exception => error
      display_message = error.response.include?('displayMessage') ? JSON.parse(error.response)['displayMessage'] : error.to_s
      notice display_message, {:level => :error}
      Rails.logger.error error.backtrace.join("\n")
      render :text => error, :status => :bad_request
    end
  end

  def index
  end

  def environments
    accesible_envs = KTEnvironment.systems_readable(current_organization)

    begin
      @systems = []
      setup_environment_selector(current_organization, accesible_envs)
      if @environment
        # add the environment id as a search filter.. this will be passed to the app by search as part of
        # the auto_complete_search requests
        @panel_options[:search_env] = @environment.id
      end
      
      render :index, :locals=>{:envsys => true, :accessible_envs=> accesible_envs}
    rescue Exception => error
      notice error.to_s, {:level => :error, :persist => false}
      render :index, :status=>:bad_request
    end
  end

  def items
    order = split_order(params[:order])
    search = params[:search]
    if params[:env_id]
      find_environment
      filters = {:environment_id=>[params[:env_id]]}
    else
      filters = {:environment_id=> KTEnvironment.systems_readable(current_organization).collect{|item| item.id}}
    end
    render_panel_direct(System, @panel_options, search, params[:offset], order,
                        {:filter=>filters, :load=>true})

  end

  def split_order order
    if order
      order.split
    else
      [:name_sort, "ASC"]
    end

  end

  def subscriptions
    consumed_entitlements = @system.consumed_entitlements
    avail_pools = @system.available_pools_full !current_user.subscriptions_match_system_preference
    facts = @system.facts.stringify_keys
    sockets = facts['cpu.cpu_socket(s)']
    render :partial=>"subscriptions", :layout => "tupane_layout",
                                      :locals=>{:system=>@system, :avail_subs => avail_pools,
                                                :consumed_entitlements => consumed_entitlements, :sockets=>sockets,
                                                :editable=>@system.editable?}
  end

  def update_subscriptions
    begin
      if params.has_key? :system
        params[:system].keys.each do |pool|
          @system.subscribe pool, params[:spinner][pool] if params[:commit].downcase == "subscribe"
          @system.unsubscribe pool if params[:commit].downcase == "unsubscribe"
        end
        consumed_entitlements = @system.consumed_entitlements
        avail_pools = @system.available_pools_full
        render :partial=>"subs_update", :locals=>{:system=>@system, :avail_subs => avail_pools,
                                                    :consumed_subs => consumed_entitlements,
                                                    :editable=>@system.editable?}
        notice _("System subscriptions updated.")

      end
    rescue Exception => error
      notice error.to_s, {:level => :error, :persist => false}
      render :nothing => true, :status => :bad_request
    end
  end

  def products
    if @system.class == Hypervisor
      render :partial=>"hypervisor", :layout=>"tupane_layout",
             :locals=>{:system=>@system,
                       :message=>_("Hypervisors do not have software products")}
      return
    end

    products , offset = first_objects @system.installedProducts.sort {|a,b| a['productName'].downcase <=> b['productName'].downcase}
    render :partial=>"products", :layout => "tupane_layout", :locals=>{:system=>@system, :products => products, :offset => offset}
  end

  def more_products
    products, offset = more_objects @system.installedProducts.sort {|a,b| a['productName'].downcase <=> b['productName'].downcase}
    render :partial=>"more_products", :locals=>{:system=>@system, :products => products, :offset=> offset}
  end

  def edit
     render :partial=>"edit", :layout=>"tupane_layout", :locals=>{:system=>@system, :editable=>@system.editable?, :name=>controller_display_name}
  end

  def update
    begin
      # The 'autoheal' flag is not an ActiveRecord attribute so update it explicitly if present
      @system.autoheal = params[:autoheal] if params[:autoheal]

      @system.update_attributes!(params[:system])
      notice _("System '#{@system["name"]}' was updated.")
      
      if not search_validate(System, @system.id, params[:search])
        notice _("'#{@system["name"]}' no longer matches the current search criteria."), { :level => :message, :synchronous_request => true }
      end

      respond_to do |format|
        format.html { render :text=>(params[:system] ? params[:system].first[1] : "") }
        format.js
      end
    rescue Exception => error
      notice error.to_s, {:level => :error, :persist => false}
      respond_to do |format|
        format.html { render :partial => "layouts/notification", :status => :bad_request, :content_type => 'text/html' and return}
        format.js { render :partial => "layouts/notification", :status => :bad_request, :content_type => 'text/html' and return}
      end
    end
  end

  def show
    system = System.find(params[:id])
    render :partial=>"systems/list_system_show", :locals=>{:item=>system, :accessor=>"id", :columns=> COLUMNS.keys, :noblock => 1}
  end

  def section_id
    'systems'
  end

  def facts
    render :partial => 'facts', :layout => "tupane_layout"
  end

  def bulk_destroy
    @systems.each{|sys|
      sys.destroy
    }
    notice _("#{@systems.length} Systems Removed Successfully")
    render :text=>""
  rescue Exception => e
    notice e, {:level => :error}
    render :text=>e, :status=>500
  end

  def destroy
    id = params[:id]
    system = find_system
    system.destroy
    if system.destroyed?
      notice _("#{system.name} Removed Successfully")
      #render and do the removal in one swoop!
      render :partial => "common/list_remove", :locals => {:id => id, :name=>controller_display_name} and return
    end
    notice "", {:level => :error, :list_items => system.errors.to_a}
    render :text => @system.errors, :status=>:ok
  rescue Exception => e
    notice e, {:level => :error}
    render :text=>e, :status=>500
  end



  private

  include SortColumnList

  def find_environment
    readable = KTEnvironment.systems_readable(current_organization)
    @environment = KTEnvironment.find(params[:env_id]) if params[:env_id]
    @environment ||= first_env_in_path(readable, false)
    @environment ||=  current_organization.library
  end

  def find_system
    @system = System.find(params[:id])
  end

  def find_systems
    @systems = System.find(params[:ids])
  end

  def setup_options
    @panel_options = { :title => _('Systems'),
                      :col => ["name", "lastCheckin"],
                      :titles => [_("Name"), _("Last Checked In")],
                      :custom_rows => true,
                      :enable_create => false, 
                      :enable_sort => true,
                      :name => controller_display_name,
                      :list_partial => 'systems/list_systems',
                      :ajax_load  => true,
                      :ajax_scroll => items_systems_path(),
                      :actions => System.deletable?(@environment, current_organization) ? 'actions' : nil,
                      :search_class=>System
                      }
  end

  def sys_consumed_pools
    consumed_pools = @system.pools.collect {|pool| OpenStruct.new(:poolId => pool["id"],
                            :poolName => pool["productName"],
                            :expires => format_time(Date.parse(pool["endDate"])),
                            :consumed => pool["consumed"],
                            :quantity => pool["quantity"])}
    consumed_pools.sort! {|a,b| a.poolName <=> b.poolName}
    consumed_pools
  end

  def sys_available_pools
    avail_pools = @system.available_pools.collect {|pool| OpenStruct.new(:poolId => pool["id"],
                            :poolName => pool["productName"],
                            :expires => format_time(Date.parse(pool["endDate"])),
                            :consumed => pool["consumed"],
                            :quantity => pool["quantity"])}
    avail_pools.sort! {|a,b| a.poolName <=> b.poolName}
    avail_pools
  end

  def controller_display_name
    return 'system'
  end

  def search_filter
    @filter = {:organization_id => current_organization}
  end

  def sort_order_limit systems
      sort_columns(COLUMNS, systems) if params[:order]
      offset = params[:offset].to_i if params[:offset]
      offset ||= 0
      last = offset + current_user.page_size
      last = systems.length if last > systems.length
      systems[offset...last]
  end

  def first_objects objects
    offset = current_user.page_size
    if objects.length > 0
      if params.has_key? :order
        if params[:order].downcase == "desc"
          objects.reverse!
        end
      end
      objects = objects[0...offset]
    else
      objects = []
    end
    return objects, offset
  end

  def more_objects objects
    #grab the current user setting for page size
    size = current_user.page_size
    if objects.length > 0
      #check for the params offset (start of array chunk)
      if params.has_key? :offset
        offset = params[:offset].to_i
      else
        offset = current_user.page_size
      end
      if params.has_key? :order
        if params[:order].downcase == "desc"
          #reverse if order is desc
          objects.reverse!
        end
      end
      if params.has_key? :reverse
        next_objects = objects[0...params[:reverse].to_i]
      else
        next_objects = objects[offset...offset+size]
      end
      next_objects ||= [] # fence for case when offset extended beyond range, etc.
    else
      next_objects = []
    end

    return next_objects, offset
  end

end