module ApplicationHelper
  include_concern 'ViewsShared'
  include_concern 'PageLayouts'
  include_concern 'Tasks'
  include Sandbox
  include CompressedIds
  include JsHelper
  include StiRoutingHelper
  include ToolbarHelper
  include TextualSummaryHelper
  include NumberHelper
  include Title

  # Need to generate paths w/o hostname by default to make proxying work.
  #
  def url_for_only_path(args)
    url_for(:only_path => true, **args)
  end

  def settings(*path)
    @settings ||= {}
    @settings.fetch_path(*path)
  end

  def settings_default(default, *path)
    settings(*path) || default
  end

  def documentation_link(url = nil, documentation_subject = "")
    if url
      link_to(_("For more information, visit the %{subject} documentation.") % {:subject => documentation_subject},
              url, :rel => 'external',
              :class => 'documentation-link', :target => '_blank')
    end
  end

  def websocket_origin
    proto = request.ssl? ? 'wss' : 'ws'
    # Retrieve the host that needs to be explicitly allowed for websocket connections
    host = if request.env['HTTP_X_FORWARDED_HOST']
             # Use the first proxy (production)
             request.env['HTTP_X_FORWARDED_HOST'].split(/,\s*/).first
           else
             # Use the HOST header (development)
             request.env['HTTP_HOST']
           end
    "#{proto}://#{host}"
  end

  def valid_html_id(id)
    id = id.to_s.gsub("::", "__")
    raise "HTML ID is not valid" if /[^\w_]/.match(id)
    id
  end

  # Create a collapsed panel based on a condition
  def miq_accordion_panel(title, condition, id, &block)
    id = valid_html_id(id)
    content_tag(:div, :class => "panel panel-default") do
      out = content_tag(:div, :class => "panel-heading") do
        content_tag(:h4, :class => "panel-title") do
          link_to(title, "##{id}",
                  'data-parent' => '#accordion',
                  'data-toggle' => 'collapse',
                  :class        => condition ? '' : 'collapsed')
        end
      end
      out << content_tag(:div, :id => id, :class => "panel-collapse collapse #{condition ? 'in' : ''}") do
        content_tag(:div, :class => "panel-body", &block)
      end
    end
  end

  def single_relationship_link(record, table_name, property_name = nil)
    out = ''
    property_name ||= table_name
    ent = record.send(property_name)
    name = ui_lookup(:table => table_name.to_s)
    if role_allows?(:feature => "#{table_name}_show") && !ent.nil?
      out = content_tag(:li) do
        link_params = if restful_routed?(ent)
                        polymorphic_path(ent)
                      else
                        {:controller => table_name, :action => 'show', :id => ent.id.to_s}
                      end
        link_to("#{name}: #{ent.name}",
                link_params,
                :title => _("Show this %{entity_name}'s parent %{linked_entity_name}") %
                          {:entity_name        => record.class.name.demodulize.titleize,
                           :linked_entity_name => name})
      end
    end
    out
  end

  def multiple_relationship_link(record, table_name)
    out = ''
    if role_allows?(:feature => "#{table_name}_show_list") &&
       (table_name != 'container_route' || record.respond_to?(:container_routes))
      plural = ui_lookup(:tables => table_name.to_s)
      count = record.number_of(table_name.to_s.pluralize)
      if count == 0
        out = content_tag(:li, :class => "disabled") do
          link_to("#{plural} (0)", "#")
        end
      else
        out = content_tag(:li) do
          if restful_routed?(record)
            link_to("#{plural} (#{count})",
                    polymorphic_path(record, :display => table_name.to_s.pluralize),
                    :title => _("Show %{plural_linked_name}") % {:plural_linked_name => plural})
          else
            link_to("#{plural} (#{count})",
                    {:controller => controller_name,
                     :action     => 'show',
                     :id         => record.id,
                     :display    => table_name.to_s.pluralize},
                    {:title => _("Show %{plural_linked_name}") % {:plural_linked_name => plural}})
          end
        end
      end
    end
    out
  end

  # Create a hidden div area based on a condition (using for hiding nav panes)
  def hidden_div_if(condition, options = {}, &block)
    hidden_tag_if(:div, condition, options, &block)
  end

  # Create a hidden span tag based on a condition (using for hiding nav panes)
  def hidden_span_if(condition, options = {}, &block)
    hidden_tag_if(:span, condition, options, &block)
  end

  def hidden_tag_if(tag, condition, options = {}, &block)
    options[:style] = "display: none" if condition
    if block_given?
      content_tag(tag, options, &block)
    else
      # TODO: Remove this old open-tag-only way in favor of block style
      tag(tag, options, true)
    end
  end

  def hover_class(item)
    if item.fetch_path(:link) ||
       item.fetch_path(:value).kind_of?(Array) &&
       item[:value].any? { |val| val[:link] }
      ''
    else
      'no-hover'
    end
  end

  # Check role based authorization for a UI task
  def role_allows?(**options)
    if options[:feature].nil?
      $log.debug("Auth failed - no feature was specified (required)")
      return false
    end

    Rbac.role_allows?(options.merge(:user => User.current_user)) rescue false
  end

  module_function :role_allows?
  public :role_allows?
  alias_method :role_allows, :role_allows?
  Vmdb::Deprecation.deprecate_methods(self, :role_allows => :role_allows?)

  # NB: This differs from controller_for_model; until they're unified,
  # make sure you have the right one.
  def model_to_controller(record)
    record.class.base_model.name.underscore
  end

  def controller_to_model
    case self.class.model.to_s
    when "ManageIQ::Providers::CloudManager::Template",
         "ManageIQ::Providers::CloudManager::Vm",
         "ManageIQ::Providers::InfraManager::Template",
         "ManageIQ::Providers::InfraManager::Vm"
      VmOrTemplate
    else
      self.class.model
    end
  end

  def restful_routed?(record_or_model)
    model = if record_or_model.kind_of?(Class)
              record_or_model
            else
              record_or_model.class
            end
    model = ui_base_model(model)
    respond_to?("#{model.model_name.route_key}_path")
  end

  def restful_routed_action?(controller = controller_name, action = action_name)
    restful_routed?(("#{controller.camelize}Controller").constantize.model) && !%w(explorer show_list).include?(action)
  rescue
    false
  end

  def url_for_record(record, action = "show") # Default action is show
    @id = to_cid(record.id)
    db  = if controller.kind_of?(VmOrTemplateController)
            "vm_or_template"
          elsif record.kind_of?(VmOrTemplate)
            controller_for_vm(model_for_vm(record))
          elsif record.class.respond_to?(:db_name)
            record.class.db_name
          elsif record.kind_of?(ManageIQ::Providers::EmbeddedAnsible::AutomationManager::Playbook)
            "ansible_playbook"
          elsif record.kind_of?(ManageIQ::Providers::EmbeddedAutomationManager::Authentication)
            "ansible_credential"
          elsif record.kind_of?(ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScriptSource)
            "ansible_repository"
          else
            record.class.base_class.to_s
          end
    url_for_db(db, action, record)
  end

  # Create a url for a record that links to the proper controller
  def url_for_db(db, action = "show", item = nil) # Default action is show
    if item && restful_routed?(item)
      return polymorphic_path(item)
    end
    if @vm && ["Account", "User", "Group", "Patch", "GuestApplication"].include?(db)
      return url_for_only_path(:controller => "vm_or_template",
                     :action     => @lastaction,
                     :id         => @vm,
                     :show       => @id
                    )
    elsif @host && ["Patch", "GuestApplication"].include?(db)
      return url_for_only_path(:controller => "host", :action => @lastaction, :id => @host, :show => @id)
    elsif %w(ConfiguredSystem ConfigurationProfile EmsFolder).include?(db)
      return url_for_only_path(:controller => "provider_foreman", :action => @lastaction, :id => @record, :show => @id)
    else
      controller, action = db_to_controller(db, action)
      return url_for_only_path(:controller => controller, :action => action, :id => @id)
    end
  end

  # Create a url to show a record from the passed in view
  def view_to_url(view, parent = nil)
    association = view_to_association(view, parent)
    if association.nil?
      controller, action = db_to_controller(view.db)
      if controller == "ems_cloud" && action == "show"
        return ems_clouds_path
      end
      if controller == "ems_infra" && action == "show"
        return ems_infras_path
      end
      if controller == "ems_physical_infra" && action == "show"
        return ems_physical_infras_path
      end
      if controller == "ems_container" && action == "show"
        return ems_containers_path
      end
      if controller == "ems_middleware" && action == "show"
        return ems_middlewares_path
      end
      if controller == "ems_datawarehouse" && action == "show"
        return ems_datawarehouses_path
      end
      if controller == "ems_network" && action == "show"
        return ems_networks_path
      end
      if @explorer
        # showing a list view of another CI inside vmx
        if %w(SecurityGroup
              FloatingIp
              NetworkRouter
              NetworkPort
              CloudNetwork
              CloudSubnet
              LoadBalancer
              CloudVolume
              ).include?(view.db)
          return url_for_only_path(:controller => controller, :action => "show") + "/"
        elsif ["Vm"].include?(view.db) && parent && request.parameters[:controller] != "vm"
          # this is to handle link to a vm in vm explorer from service explorer
          return url_for_only_path(:controller => "vm_or_template", :action => "show") + "/"
        elsif %w(ConfigurationProfile EmsFolder).include?(view.db) &&
              request.parameters[:controller] == "provider_foreman"
          return url_for_only_path(:action => action, :id => nil) + "/"
        elsif %w(ManageIQ::Providers::AutomationManager::InventoryGroup EmsFolder).include?(view.db) &&
              request.parameters[:controller] == "automation_manager"
          return url_for_only_path(:action => action, :id => nil) + "/"
        elsif %w(ConfiguredSystem).include?(view.db) && (request.parameters[:controller] == "provider_foreman" || request.parameters[:controller] == "automation_manager")
          return url_for_only_path(:action => action, :id => nil) + "/"
        else
          return url_for_only_path(:action => action) + "/" # In explorer, don't jump to other controllers
        end
      else
        controller = "vm_cloud" if controller == "template_cloud"
        controller = "vm_infra" if controller == "template_infra"
        return url_for_only_path(:controller => controller, :action => action, :id => nil) + "/"
      end

    else
      # need to add a check for @explorer while setting controller incase building a link for details screen to show items
      # i.e users list view screen inside explorer needs to point to vm_or_template controller
      return url_for_only_path(:controller => parent.kind_of?(VmOrTemplate) && !@explorer ? parent.class.base_model.to_s.underscore : request.parameters["controller"],
                     :action     => association,
                     :id         => parent.id) + "?#{@explorer ? "x_show" : "show"}="
    end
  end

  def view_to_association(view, parent)
    case view.db
    when "OrchestrationStackOutput"    then "outputs"
    when "OrchestrationStackParameter" then "parameters"
    when "OrchestrationStackResource"  then "resources"
    when 'AdvancedSetting', 'Filesystem', 'FirewallRule', 'GuestApplication', 'Patch',
         'RegistryItem', 'ScanHistory', 'OpenscapRuleResult'
                                       then view.db.tableize
    when "SystemService"
      case parent.class.base_class.to_s.downcase
      when "host" then "host_services"
      when "vm"   then @lastaction
      end
    when "CloudService" then "host_cloud_services"
    else view.scoped_association
    end
  end

  # Convert a db name to a controller name and an action
  def db_to_controller(db, action = "show")
    action = "x_show" if @explorer
    case db
    when "ActionSet"
      controller = "miq_action"
      action = "show_set"
    when "AutomationRequest"
      controller = "miq_request"
      action = "show"
    when "ConditionSet"
      controller = "condition"
    when "ManageIQ::Providers::EmbeddedAutomationManager::ConfigurationScriptSource"
      controller = "ansible_repository"
    when "ScanItemSet"
      controller = "ops"
      action = "ap_show"
    when "MiqEventDefinition"
      controller = "event"
      action = "_none_"
    when "User", "Group", "Patch", "GuestApplication"
      controller = "vm"
      action = @lastaction
    when "Host" && action == 'x_show'
      controller = "infra_networking"
      action = @lastaction
    when "MiqReportResult"
      controller = "report"
      action = "show_saved"
    when "MiqSchedule"
      if request.parameters["controller"] == "report"
        controller = "report"
        action = "show_schedule"
      else
        controller = "ops"
        action = "schedule_show"
      end
    when "MiqAeClass"
      controller = "miq_ae_class"
      action = "show_instances"
    when "MiqAeInstance"
      controller = "miq_ae_class"
      action = "show_details"
    when "SecurityGroup"
      controller = "security_group"
      action = "show"
    when "ServiceResource", "ServiceTemplate"
      controller = "catalog"
    when "ManageIQ::Providers::EmbeddedAnsible::AutomationManager::Playbook"
      controller = "ansible_playbook"
    when "ManageIQ::Providers::EmbeddedAutomationManager::Authentication"
      controller = "ansible_credential"
    when "MiqWorker"
      controller = request.parameters[:controller]
      action = "diagnostics_worker_selected"
    when "OrchestrationStackOutput", "OrchestrationStackParameter", "OrchestrationStackResource",
        "ManageIQ::Providers::CloudManager::OrchestrationStack",
        "ManageIQ::Providers::AnsibleTower::AutomationManager::Job"
      controller = request.parameters[:controller]
    when "ContainerVolume"
      controller = "persistent_volume"
    when /^ManageIQ::Providers::(\w+)Manager$/
      controller = "ems_#{$1.underscore}"
    when /^ManageIQ::Providers::(\w+)Manager::(\w+)$/
      controller = "#{$2.underscore}_#{$1.underscore}"
    else
      controller = db.underscore
    end
    return controller, action
  end

  # Method to create the center toolbar XML
  def build_toolbar(tb_name)
    _toolbar_builder.call(tb_name)
  end

  def _toolbar_builder
    ToolbarBuilder.new(
      self,
      binding,
      :active                => @active,
      :button_group          => @button_group,
      :changed               => @changed,
      :condition             => @condition,
      :condition_policy      => @condition_policy,
      :db                    => @db,
      :display               => @display,
      :edit                  => @edit,
      :explorer              => @explorer,
      :ght_type              => @ght_type,
      :gtl_buttons           => @gtl_buttons,
      :gtl_type              => @gtl_type,
      :html                  => @html,
      :lastaction            => @lastaction,
      :layout                => @layout,
      :miq_request           => @miq_request,
      :msg_title             => @msg_title,
      :perf_options          => @perf_options,
      :policy                => @policy,
      :record                => @record,
      :report                => @report,
      :report_result_id      => @report_result_id,
      :resolve               => @resolve,
      :sb                    => @sb,
      :selected_zone         => @selected_zone,
      :settings              => @settings,
      :showtype              => @showtype,
      :tabform               => @tabform,
      :widget_running        => @widget_running,
      :widgetsets            => @widgetsets,
      :zgraph                => @zgraph,
    )
  end

  # Convert a field (Vm.hardware.disks-size) to a col (disks.size)
  def field_to_col(field)
    dbs, fld = field.split("-")
    (dbs.include?(".") ? "#{dbs.split(".").last}.#{fld}" : fld)
  end

  def controller_model_name(controller)
    ui_lookup(:model => (controller.camelize + "Controller").constantize.model.name)
  end

  def is_browser_ie?
    browser_info(:name) == "explorer"
  end

  def is_browser_ie7?
    is_browser_ie? && browser_info(:version).starts_with?("7")
  end

  def is_browser?(name)
    browser_name = browser_info(:name)
    name.kind_of?(Array) ? name.include?(browser_name) : (browser_name == name)
  end

  def is_browser_os?(os)
    browser_os = browser_info(:os)
    os.kind_of?(Array) ? os.include?(browser_os) : (browser_os == os)
  end

  def browser_info(typ)
    session.fetch_path(:browser, typ).to_s
  end

  ############# Following methods generate JS lines for render page blocks
  def javascript_for_timer_type(timer_type)
    case timer_type
    when "Monthly"
      [
        javascript_hide("weekly_span"),
        javascript_hide("daily_span"),
        javascript_hide("hourly_span"),
        javascript_show("monthly_span")
      ]
    when "Weekly"
      [
        javascript_hide("daily_span"),
        javascript_hide("hourly_span"),
        javascript_hide("monthly_span"),
        javascript_show("weekly_span")
      ]
    when "Daily"
      [
        javascript_hide("hourly_span"),
        javascript_hide("monthly_span"),
        javascript_hide("weekly_span"),
        javascript_show("daily_span")
      ]
    when "Hourly"
      [
        javascript_hide("daily_span"),
        javascript_hide("monthly_span"),
        javascript_hide("weekly_span"),
        javascript_show("hourly_span")
      ]
    when nil
      []
    else
      [
        javascript_hide("daily_span"),
        javascript_hide("hourly_span"),
        javascript_hide("monthly_span"),
        javascript_hide("weekly_span")
      ]
    end
  end

  # Show/hide the Save and Reset buttons based on whether changes have been made
  def javascript_for_miq_button_visibility(display, prefix = nil)
    if prefix
      "miqButtons('#{display ? 'show' : 'hide'}', '#{prefix}');".html_safe
    else
      "miqButtons('#{display ? 'show' : 'hide'}');".html_safe
    end
  end

  def javascript_for_miq_button_visibility_changed(changed)
    return "" if changed == session[:changed]
    session[:changed] = changed
    javascript_for_miq_button_visibility(changed)
  end

  def javascript_pf_toolbar_reload(div_id, toolbar)
    "sendDataWithRx({redrawToolbar: #{toolbar_from_hash.to_json}});"
  end

  def set_edit_timer_from_schedule(schedule)
    @edit[:new][:timer] ||= ReportHelper::Timer.new
    if schedule.run_at.nil?
      t = Time.now.in_time_zone(@edit[:tz]) + 1.day # Default date/time to tomorrow in selected time zone
      @edit[:new][:timer].typ = 'Once'
      @edit[:new][:timer].start_date = "#{t.month}/#{t.day}/#{t.year}"
    else
      @edit[:new][:timer].update_from_miq_schedule(schedule.run_at, @edit[:tz])
    end
  end

  # Check if a parent chart has been selected and applies
  def perf_parent?
    @perf_options[:model] == "VmOrTemplate" &&
      @perf_options[:typ] != "realtime" &&
      VALID_PERF_PARENTS.keys.include?(@perf_options[:parent])
  end

  # Determine the type of report (performance/trend/chargeback) based on the model
  def model_report_type(model)
    if model
      if model.ends_with?("Performance", "MetricsRollup")
        return :performance
      elsif model == UiConstants::TREND_MODEL
        return :trend
      elsif model.starts_with?("Chargeback")
        return model.downcase.to_sym
      end
    end
    nil
  end

  def taskbar_in_header?
    if @show_taskbar.nil?
      @show_taskbar = false
      if ! (@layout == "" &&
        %w(auth_error
           change_tab
           show
          ).include?(controller.action_name) ||
        %w(about
           chargeback
           cloud_topology
           container_dashboard
           ems_infra_dashboard
           exception
           infra_topology
           middleware_topology
           miq_ae_automate_button
           miq_ae_class
           miq_ae_export
           miq_ae_tools
           miq_capacity_bottlenecks
           miq_capacity_planning
           miq_capacity_utilization
           miq_capacity_waste
           miq_policy
           miq_policy_export
           miq_policy_rsop
           monitor_alerts_overview
           monitor_alerts_list
           monitor_alerts_most_recent
           network_topology
           ops
           physical_infra_topology
           pxe
           report
           rss
           server_build
          ).include?(@layout) ||
        (@layout == "configuration" && @tabform != "ui_4")) && !controller.action_name.end_with?("tagging_edit")
        unless @explorer
          @show_taskbar = true
        end
      end
    end
    @show_taskbar
  end

  # checking if any of the toolbar is visible
  def toolbars_visible?
    (@toolbars['history_tb'] || @toolbars['center_tb'] || @toolbars['view_tb']) &&
    (@toolbars['history_tb'] != 'blank_view_tb' && @toolbars['history_tb'] != 'blank_view_tb' && @toolbars['view_tb'] != 'blank_view_tb')
  end

  def inner_layout_present?
    if @inner_layout_present.nil?
      @inner_layout_present = false
      if @explorer || params[:action] == "explorer" ||
         (params[:controller] == "chargeback" && params[:action] == "chargeback") ||
         (params[:controller] == "miq_ae_tools" && (params[:action] == "resolve" || params[:action] == "show")) ||
         (params[:controller] == "miq_policy" && params[:action] == "rsop") ||
         (params[:controller] == "miq_capacity")
        @inner_layout_present = true
      end
    end
    @inner_layout_present
  end

  # Format a column in a report view for display on the screen
  def format_col_for_display(view, row, col, tz = nil)
    tz ||= ["miqschedule"].include?(view.db.downcase) ? MiqServer.my_server.server_timezone : Time.zone
    celltext = view.format(col,
                           row[col],
                           :tz => tz
                          ).gsub(/\\/, '\&')    # Call format, then escape any backslashes
    celltext
  end

  def check_if_button_is_implemented
    if !@flash_array && !@refresh_partial # if no button handler ran, show not implemented msg
      add_flash(_("Button not yet implemented"), :error)
      @refresh_partial = "layouts/flash_msg"
      @refresh_div = "flash_msg_div"
    elsif @flash_array && @lastaction == "show"
      @ems = @record = identify_record(params[:id])
      @refresh_partial = "layouts/flash_msg"
      @refresh_div = "flash_msg_div"
    end
  end

  # Return a blank tb if a placeholder is needed for AJAX explorer screens, return nil if no center toolbar to be shown
  def center_toolbar_filename
    _toolbar_chooser.center_toolbar_filename
  end

  def history_toolbar_filename
    _toolbar_chooser.history_toolbar_filename
  end

  def x_view_toolbar_filename
    _toolbar_chooser.x_view_toolbar_filename
  end

  def view_toolbar_filename
    _toolbar_chooser.view_toolbar_filename
  end

  def _toolbar_chooser
    ToolbarChooser.new(
      self,
      binding,
      :alert_profiles => @alert_profiles,
      :button_group   => @button_group,
      :conditions     => @conditions,
      :dialog         => @dialog,
      :display        => @display,
      :explorer       => @explorer,
      :in_a_form      => @in_a_form,
      :lastaction     => @lastaction,
      :layout         => @layout,
      :nodetype       => @nodetype,
      :policies       => @policies,
      :record         => @record,
      :report         => @report,
      :sb             => @sb,
      :showtype       => @showtype,
      :tabform        => @tabform,
      :view           => @view,
      :center_toolbar => @center_toolbar
    )
  end

  # Calculate hash of toolbars to render
  #
  # keys are toolbar <div> names and values are toobar identifiers (now YAML files)
  #
  def calculate_toolbars
    toolbars = {}
    if inner_layout_present? # x_taskbar branch
      toolbars['history_tb'] = history_toolbar_filename
    elsif display_back_button? # taskbar branch
      toolbars['summary_center_tb'] = controller.restful? ? "summary_center_restful_tb" : "summary_center_tb"
    end

    toolbars['center_tb'] = center_toolbar_filename

    custom_toolbar = controller.custom_toolbar?
    if custom_toolbar
      toolbars['custom_tb'] = custom_toolbar == :blank ? 'blank_view_tb' : 'custom_buttons_tb'
    end

    toolbars['view_tb'] = inner_layout_present? ? x_view_toolbar_filename : view_toolbar_filename
    toolbars
  end

  # check if back to summary button needs to be show
  def display_back_button?
    # don't need to back button if @record is not there or @record doesnt have name or
    # evm_display_name column, i.e MiqProvisionRequest
    if (@lastaction != "show" || (@lastaction == "show" && @display != "main")) &&
       @record &&
       (@record.respond_to?('name') && !@record.name.nil?)
      return true
    else
      return false
    end
  end

  def display_adv_search?
    %w(auth_key_pair_cloud
       availability_zone
       automation_manager
       cloud_network
       cloud_object_store_container
       cloud_subnet
       cloud_tenant
       cloud_volume
       configuration_job
       container_build
       container_group
       container_image
       container_image_registry
       container_node
       container_project
       container_replicator
       container_route
       container_service
       container_template
       ems_cloud
       ems_cluster
       ems_container
       ems_infra
       ems_middleware
       ems_network
       ems_physical_infra
       ems_storage
       flavor
       floating_ip
       host
       host_aggregate
       load_balancer
       middleware_datasource
       middleware_deployment
       middleware_domain
       middleware_messaging
       middleware_server
       miq_template
       network_port
       network_router
       offline
       orchestration_stack
       persistent_volume
       provider_foreman
       resource_pool
       retired
       security_group
       service
       storage
       storage_manager
       templates
       vm
      ).include?(@layout)
  end

  # Do we show or hide the clear_search link in the list view title
  def clear_search_status
    !!(@edit && @edit.fetch_path(:adv_search_applied, :text))
  end

  # Should we allow the user input checkbox be shown for an atom in the expression editor
  QS_VALID_USER_INPUT_OPERATORS = ["=", "!=", ">", ">=", "<", "<=", "INCLUDES", "STARTS WITH", "ENDS WITH", "CONTAINS"]
  QS_VALID_FIELD_TYPES = [:string, :boolean, :integer, :float, :percent, :bytes, :megabytes]
  def qs_show_user_input_checkbox?
    return false unless @edit[:adv_search_open]  # Only allow user input for advanced searches
    return false unless QS_VALID_USER_INPUT_OPERATORS.include?(@edit[@expkey][:exp_key])
    val = (@edit[@expkey][:exp_typ] == "field" && # Field atoms with certain field types return true
           QS_VALID_FIELD_TYPES.include?(@edit[@expkey][:val1][:type])) ||
          (@edit[@expkey][:exp_typ] == "tag" && # Tag atoms with a tag category chosen return true
           @edit[@expkey][:exp_tag]) ||
          (@edit[@expkey][:exp_typ] == "count" && # Count atoms with a count col chosen return true
              @edit[@expkey][:exp_count])
    val
  end

  # Should we allow the field alias checkbox to be shown for an atom in the expression editor
  def adv_search_show_alias_checkbox?
    @edit[:adv_search_open]  # Only allow field aliases for advanced searches
  end

  def saved_report_paging?
    # saved report doesn't use miq_report object,
    # need to use a different paging view to page thru a saved report
    @sb[:pages] && @html && [:reports_tree, :savedreports_tree, :cb_reports_tree].include?(x_active_tree)
  end

  def pressed2model_action(pressed)
    pressed =~ /^(ems_cluster|miq_template|infra_networking)_(.*)$/ ? [$1, $2] : pressed.split('_', 2)
  end

  def model_for_ems(record)
    raise _("Record is not ExtManagementSystem class") unless record.kind_of?(ExtManagementSystem)
    if record.kind_of?(ManageIQ::Providers::CloudManager)
      ManageIQ::Providers::CloudManager
    elsif record.kind_of?(ManageIQ::Providers::ContainerManager)
      ManageIQ::Providers::ContainerManager
    else
      ManageIQ::Providers::InfraManager
    end
  end

  def model_for_vm(record)
    raise _("Record is not VmOrTemplate class") unless record.kind_of?(VmOrTemplate)
    if record.kind_of?(ManageIQ::Providers::CloudManager::Vm)
      ManageIQ::Providers::CloudManager::Vm
    elsif record.kind_of?(ManageIQ::Providers::InfraManager::Vm)
      ManageIQ::Providers::InfraManager::Vm
    elsif record.kind_of?(ManageIQ::Providers::CloudManager::Template)
      ManageIQ::Providers::CloudManager::Template
    elsif record.kind_of?(ManageIQ::Providers::InfraManager::Template)
      ManageIQ::Providers::InfraManager::Template
    end
  end

  def controller_for_vm(model)
    case model.to_s
    when "ManageIQ::Providers::CloudManager::Template", "ManageIQ::Providers::CloudManager::Vm"
      "vm_cloud"
    when "ManageIQ::Providers::InfraManager::Template", "ManageIQ::Providers::InfraManager::Vm"
      "vm_infra"
    else
      "vm_or_template"
    end
  end

  def controller_for_stack(model)
    case model.to_s
    when "ManageIQ::Providers::AnsibleTower::AutomationManager::Job"
      "configuration_job"
    else
      model.name.underscore
    end
  end

  def vm_model_from_active_tree(tree)
    case tree
    when :instances_filter_tree
      "ManageIQ::Providers::CloudManager::Vm"
    when :images_filter_tree
      "ManageIQ::Providers::CloudManager::Template"
    when :vms_filter_tree
      "ManageIQ::Providers::InfraManager::Vm"
    when :templates_filter_tree
      "ManageIQ::Providers::InfraManager::Template"
    when :templates_images_filter_tree
      "MiqTemplate"
    when :vms_instances_filter_tree
      "Vm"
    end
  end

  def object_types_for_flash_message(klass, record_ids)
    if klass == VmOrTemplate
      object_ary = klass.where(:id => record_ids).collect { |rec| ui_lookup(:model => model_for_vm(rec).to_s) }
      obj_hash = object_ary.each.with_object(Hash.new(0)) { |obj, h| h[obj] += 1 }
      obj_hash.collect { |k, v| v == 1 ? k : k.pluralize }.sort.to_sentence
    else
      object = ui_lookup(:model => klass.to_s)
      record_ids.length == 1 ? object : object.pluralize
    end
  end

  # Function returns a HTML fragment that represents a link to related entity
  # or list of related entities of certain type in case of a condition being
  # met or information about non-existence of such entity if condition is not
  # met.
  #
  # args
  #     :if           --- bool    - the condition to be met
  #                                 if no condition is passed, it's considered true
  #     :table/tables --- string  - name of entity
  #                               - determines singular/plural case
  #     :link_text    --- string  - to override calculated link text
  #     :display      --- string  - type of display (timeline/performance/main/....)
  #     :[count]      --- fixnum  - number of entities, must be set if :tables
  #                                 is used
  #   args to construct URL
  #     :[controller] --- controller name
  #     :[action]     --- controller action
  #     :record_id    --- id of record
  #
  def li_link(args)
    args[:if] = (args[:count] != 0) if args[:count]
    args[:if] = true unless args.key?(:if)

    link_text, title = build_link_text(args)

    if args[:if]
      link_params = {
        :action  => args[:action].present? ? args[:action] : 'show',
        :display => args[:display],
        :id      => args[:record].present? ? args[:record].id : args[:record_id].to_s
      }
      link_params[:controller] = args[:controller] if args.key?(:controller)

      tag_attrs = {:title => title}
      check_changes = args[:check_changes] || args[:check_changes].nil?
      tag_attrs[:onclick] = 'return miqCheckForChanges()' if check_changes
      content_tag(:li) do
        link_args = {:display => args[:display], :vat => args[:vat]}.compact
        if args[:record] && restful_routed?(args[:record])
          link_to(link_text, polymorphic_path(args[:record], link_args), tag_attrs)
        else
          link_to(link_text, link_params, tag_attrs)
        end
      end
    else
      tag_attrs_disabled = {:title => args[:disabled_title]}
      content_tag(:li, :class => "disabled") do
        link_to(link_text, "#", tag_attrs_disabled)
      end
    end
  end

  def build_link_text(args)
    if args.key?(:tables)
      entity_name = ui_lookup(:tables => args[:tables])
      link_text   = args.key?(:link_text) ? "#{args[:link_text]} (#{args[:count]})" : "#{entity_name} (#{args[:count]})"
      title       = _("Show all %{names}") % {:names => entity_name}
    elsif args.key?(:text)
      count     = args[:count] ? "(#{args[:count]})" : ""
      link_text = "#{args[:text]} #{count}"
    elsif args.key?(:table)
      entity_name = ui_lookup(:table => args[:table])
      link_text   = args.key?(:link_text) ? args[:link_text] : entity_name
      link_text   = "#{link_text} (#{args[:count]})" if args.key?(:count)
      title       = _("Show %{name}") % {:name => entity_name}
    end
    title = args[:title] if args.key?(:title)
    return link_text, title
  end

  # Function returns a HTML fragment that represents an image with certain
  # options or an image with link and different options in case of a condition
  # has a true or a false value.
  #
  # args
  #     :cond         --- bool    - the condition to be met
  #     :image        --- string  - the URL of the image
  #     :opts_true    --- hash    - HTML options for image_tag() if cond == true
  #     :opts_false   --- hash    - HTML options for image_tag() if cond == false
  #     :link         --- hash    - options for link_to()
  #     :opts_link    --- hash    - HTML options for link_to()
  #
  def link_image_if(args)
    if args[:cond]
      image_tag(args[:image], args[:opts_true])
    else
      link_to(image_tag(args[:image], args[:opts_false]), args[:link], args[:opts_link])
    end
  end

  def link_to_with_icon(link_text, link_params, tag_args, _image_path = nil)
    tag_args ||= {}
    default_tag_args = {:onclick => "return miqCheckForChanges()"}
    tag_args = default_tag_args.merge(tag_args)
    link_to(link_text, link_params, tag_args)
  end

  def primary_nav_class(nav_id)
    test_layout = @layout
    # FIXME: exception behavior to remove
    test_layout = 'my_tasks' if %w(my_tasks my_ui_tasks all_tasks all_ui_tasks).include?(@layout)
    test_layout = 'cloud_volume' if @layout == 'cloud_volume_snapshot' || @layout == 'cloud_volume_backup'
    test_layout = 'cloud_object_store_container' if @layout == 'cloud_object_store_object'

    Menu::Manager.item_in_section?(test_layout, nav_id) ? 'active' : nil
  end

  def secondary_nav_class(item)
    item.items.collect(&:id).include?(@layout) ? 'active' : nil
  end

  def tertiary_nav_class(item)
    item.id == @layout ? 'active' : nil
  end

  def render_flash_msg?
    # Don't render flash message in gtl, partial is already being rendered on screen
    return false if request.parameters[:controller] == "miq_request" && @lastaction == "show_list"
    return false if request.parameters[:controller] == "service" && @lastaction == "show" && @view
    true
  end

  def pagination_request?
    params[:ppsetting] || params[:searchtag] || params[:entry] ||
      params[:sortby] || params[:sort_choice]
  end

  # FIXME: params[:type] is used in multiple contexts, we should rename it to
  # :gtl_type or remove it as we move to the Angular GTL component
  def pagination_or_gtl_request?
    pagination_request? || params[:type] || params[:page]
  end

  def update_gtl_div(action_url = 'explorer', button_div = 'center_tb')
    render :update do |page|
      page << javascript_prologue
      page.replace("gtl_div",
                   :partial => "layouts/x_gtl",
                   :locals  => {:action_url => action_url, :button_div => button_div})
      page.replace_html("paging_div", :partial => "layouts/x_pagingcontrols")
      page << "miqSparkle(false)"
    end
  end

  def perfmenu_click?
    return false unless params[:menu_click]
    perf_menu_click
    true
  end

  def javascript_process_redirect_args(args)
    # there's no model for ResourceController - defaulting to traditional routing
    begin
      model = self.class.model
    rescue => _err
      model = nil
    end
    if model && args.class == Hash && args[:action] == 'show' && restful_routed?(model)
      args.delete(:action)
      polymorphic_path_redirect(model, args)
    else
      args
    end
  end

  def javascript_redirect(args)
    render :update do |page|
      page << javascript_prologue
      page.redirect_to args
    end
  end

  def polymorphic_path_redirect(model, args)
    record = args[:record] ? args[:record] : model.find(args[:id] || params[:id])
    args.delete(:record)
    args.delete(:id)
    polymorphic_path(record, args)
  end

  def javascript_flash(**args)
    add_flash(args[:text], args[:severity]) if args[:text].present?

    flash_div_id = args.key?(:flash_div_id) ? args[:flash_div_id] : 'flash_msg_div'
    ex = ExplorerPresenter.flash.replace(flash_div_id,
                                         render_to_string(:partial => "layouts/flash_msg",
                                                          :locals => {:flash_div_id => flash_div_id}))
    ex.scroll_top if args[:scroll_top]
    ex.spinner_off if args[:spinner_off]
    ex.focus(args[:focus]) if args[:focus]
    ex.activate_tree_node(args[:activate_node]) if args[:activate_node]

    render :json => ex.for_render
  end

  def javascript_open_window(url)
    ex = ExplorerPresenter.open_window(url)
    ex.spinner_off
    render :json => ex.for_render
  end

  # this keeps the main_div wrapping tag, replaces only the inside
  def replace_main_div(args, options = {})
    ex = ExplorerPresenter.main_div.update('main_div', render_to_string(args))

    ex.replace("flash_msg_div", render_to_string(:partial => "layouts/flash_msg")) if options[:flash]
    ex.spinner_off if options[:spinner_off]

    render :json => ex.for_render
  end

  def javascript_miq_button_visibility(changed)
    render :json => ExplorerPresenter.buttons(changed).for_render
  end

  def record_no_longer_exists?(what, model = nil)
    return false unless what.nil?

    if !@bang || @flash_array.empty?
      # We already added a better flash message in 'identify_record'
      # in that case we keep that flash message
      # otherwise we make a new one.
      # FIXME: a refactoring of identify_record and related is needed
      add_flash(
        if model.present?
          _("%{model} no longer exists") % {:model => ui_lookup(:model => model)}
        else
          _("Error: Record no longer exists in the database")
        end,
        :error, true)
      session[:flash_msgs] = @flash_array
    end

    # Error message is displayed in 'show_list' action if such action exists
    # otherwise we assume that the 'explorer' action must exist that will display it.
    redirect_to(:action => respond_to?(:show_list) ? 'show_list' : 'explorer')
  end

  def pdf_page_size_style
    "#{@options[:page_size] || "US-Legal"} #{@options[:page_layout]}"
  end

  GTL_VIEW_LAYOUTS = %w(action
                        auth_key_pair_cloud
                        availability_zone
                        alerts_overview
                        alerts_list
                        alerts_most_recent
                        cloud_network
                        cloud_object_store_container
                        cloud_object_store_object
                        cloud_subnet
                        cloud_tenant
                        cloud_topology
                        cloud_volume
                        cloud_volume_backup
                        cloud_volume_snapshot
                        condition
                        configuration_job
                        configuration_script_source
                        container_build
                        container_dashboard
                        container_group
                        container_image
                        container_image_registry
                        container_node
                        container_project
                        container_replicator
                        container_route
                        container_service
                        container_template
                        container_topology
                        ems_cloud
                        ems_cluster
                        ems_container
                        ems_infra
                        ems_infra_dashboard
                        ems_middleware
                        ems_network
                        ems_physical_infra
                        ems_storage
                        infra_topology
                        event
                        flavor
                        floating_ip
                        host
                        host_aggregate
                        load_balancer
                        manageiq/providers/embedded_ansible/automation_manager/playbook
                        manageiq/providers/embedded_automation_manager/authentication
                        middleware_datasource
                        middleware_deployment
                        middleware_domain
                        middleware_messaging
                        middleware_server
                        middleware_server_group
                        middleware_topology
                        miq_schedule
                        miq_template
                        monitor_alerts_overview
                        monitor_alerts_list
                        monitor_alerts_most_recent
                        network_port
                        network_router
                        network_topology
                        offline
                        orchestration_stack
                        physical_infra_topology
                        persistent_volume
                        policy
                        policy_group
                        policy_profile
                        resource_pool
                        retired
                        scan_profile
                        security_group
                        service
                        storage
                        storage_manager
                        templates
                      )

  def render_gtl_view_tb?
    GTL_VIEW_LAYOUTS.include?(@layout) && @gtl_type && !@tagitems &&
      !@ownershipitems && !@retireitems && !@politems && !@in_a_form &&
      %w(show show_list).include?(params[:action])
  end

  def update_paging_url_parms(action_url, parameter_to_update = {}, post = false)
    url = update_query_string_params(parameter_to_update)
    action, an_id = action_url.split("/", 2)
    if !post && controller.restful? && action == 'show'
      polymorphic_path(@record, url)
    else
      url[:action] = action
      url[:id] = an_id unless an_id.nil?
      url_for_only_path(url)
    end
  end

  def update_query_string_params(update_this_param)
    exclude_params = %w(button flash_msg page ppsetting pressed sortby sort_choice type)
    query_string = Rack::Utils.parse_query URI("?#{request.query_string}").query
    updated_query_string = query_string.symbolize_keys
    updated_query_string.delete_if { |k, _v| exclude_params.include? k.to_s }
    updated_query_string.merge!(update_this_param)
  end

  def placeholder_if_present(password)
    password.present? ? "\u25cf" * 8 : ''
  end

  def render_listnav_filename
    if @lastaction == "show_list" && !session[:menu_click] &&
       %w(auth_key_pair_cloud
          availability_zone
          cloud_network
          cloud_object_store_container
          cloud_object_store_object
          cloud_subnet
          cloud_tenant
          cloud_volume
          cloud_volume_backup
          cloud_volume_snapshot
          configuration_job
          container_build
          container_group
          container_image
          container_image_registry
          container_node
          container_project
          container_replicator
          container_route
          container_service
          container_template
          ems_cloud
          ems_cluster
          ems_container
          ems_datawarehouse
          ems_infra
          ems_middleware
          ems_network
          ems_physical_infra
          ems_storage
          flavor
          floating_ip
          host
          middleware_datasource
          middleware_deployment
          middleware_domain
          middleware_messaging
          middleware_server
          middleware_server_group
          miq_template
          network_port
          network_router
          offline
          orchestration_stack
          persistent_volume
          resource_pool
          retired
          security_group
          service
          storage
          templates
          vm).include?(@layout) && !@in_a_form
      "show_list"
    elsif @compare
      "compare_sections"
    elsif @explorer
      "explorer"
    elsif %w(offline
             retired
             templates
             vm
             vm_cloud
             vm_or_template).include?(@layout)
      "vm"
    elsif %w(action
             auth_key_pair_cloud
             availability_zone
             cloud_network
             cloud_object_store_container
             cloud_object_store_object
             cloud_subnet
             cloud_tenant
             cloud_volume
             cloud_volume_backup
             cloud_volume_snapshot
             condition
             configuration_job
             container_build
             container_group
             container_image
             container_image_registry
             container_node
             container_project
             container_replicator
             container_route
             container_service
             container_template
             ems_cloud
             ems_cluster
             ems_container
             ems_datawarehouse
             ems_infra
             ems_middleware
             ems_network
             ems_physical_infra
             ems_storage
             flavor
             floating_ip
             host
             host_aggregate
             load_balancer
             middleware_datasource
             middleware_deployment
             middleware_domain
             middleware_messaging
             middleware_server
             middleware_server_group
             miq_schedule
             miq_template
             network_port
             network_router
             orchestration_stack
             persistent_volume
             policy
             resource_pool
             scan_profile
             security_group
             service
             storage_manager
             timeline).include?(@layout)
      @layout
    end
  end

  def show_adv_search?
    show_search = %w(
      auth_key_pair_cloud
      availability_zone
      automation_manager
      cloud_network
      cloud_object_store_container
      cloud_subnet
      cloud_tenant
      cloud_volume
      cloud_volume_backup
      cloud_volume_snapshot
      configuration_job
      container_build
      container_group
      container_image
      container_image_registry
      container_node
      container_project
      container_replicator
      container_route
      container_service
      container_template
      ems_cloud
      ems_cluster
      ems_container
      ems_infra
      ems_middleware
      ems_network
      ems_physical_infra
      ems_storage
      flavor
      floating_ip
      host
      host_aggregate
      load_balancer
      middleware_datasource
      middleware_deployment
      middleware_domain
      middleware_messaging
      middleware_server
      miq_template
      network_port
      network_router
      offline
      orchestration_stack
      persistent_volume
      provider_foreman
      resource_pool
      retired
      security_group
      service
      storage_manager
      templates
      vm
    )

    (@lastaction == "show_list" && !session[:menu_click] && show_search.include?(@layout) && !@in_a_form) ||
      (@explorer && x_tree && tree_with_advanced_search? && !@record)
  end

  def db_for_quadicon
    case @layout
    when "ems_infra"
      :ems
    when "ems_cloud"
      :ems_cloud
    else
      :ems_container
    end
  end

  def title_for_host_record(record)
    record.openstack_host? ? _("Node") : _("Host")
  end

  def title_for_cluster_record(record)
    record.openstack_cluster? ? _("Deployment Role") : _("Cluster")
  end

  def miq_tab_header(id, active = nil, options = {}, &_block)
    tag_options = {:class => "#{options[:class]} #{active == id ? 'active' : ''}",
                   :id    => "#{id}_tab"}

    tag_options['ng-click'] = options['ng-click'] if options.key?('ng-click')
    tag_options[:onclick] = options[:onclick] if options.key?(:onclick)

    content_tag(:li, tag_options) do
      content_tag(:a, :href => "##{id}", 'data-toggle' => 'tab') do
        yield
      end
    end
  end

  def miq_tab_content(id, active = nil, options = {}, &_block)
    lazy = options[:lazy] && active != id

    classname = %w(tab-pane)
    classname << options[:class] if options[:class]
    classname << 'active' if active == id
    classname << 'lazy' if lazy

    content_tag(:div, :id => id, :class => classname.join(' ')) do
      yield unless lazy
    end
  end

  def tree_with_advanced_search?
    %i(automation_manager_providers
       automation_manager_cs_filter
       containers
       containers_filter
       configuration_manager_cs_filter
       configuration_scripts
       configuration_manager_providers
       images
       images_filter
       instances
       instances_filter
       providers
       storage
       templates_filter
       templates_images_filter
       vandt
       vms_filter
       vms_instances_filter
      ).include?(x_tree[:type])
  end

  def show_advanced_search?
    x_tree && ((tree_with_advanced_search? && !@record) || @show_adv_search)
  end

  def listicon_image_tag(db, row)
    icon = nil
    if %w(Job MiqTask).include?(db)
      if row["state"].downcase == "finished" && row["status"]
        title = _("Status = %{row}") % {:row => row["status"].capitalize}
        cancel_msg = row["message"].include?('cancel')
        if row["status"].downcase == "ok" && !cancel_msg
          icon = "pficon pficon-ok"
        elsif row["status"].downcase == "error" || cancel_msg
          icon = "pficon pficon-error-circle-o"
        elsif row["status"].downcase == "warn" || cancel_msg
          icon = "pficon pficon-warning-triangle-o"
        end
      elsif %w(queued waiting_to_start).include?(row["state"].downcase)
        icon = "fa fa-step-forward"
        title = _("Status = Queued")
      elsif !%w(finished queued waiting_to_start).include?(row["state"].downcase)
        icon = "pficon pficon-running"
        title = _("Status = Running")
      end
    elsif %w(Vm VmOrTemplate).include?(db)
      vm = @targets_hash[from_cid(@id)]
      vendor = vm ? vm.vendor : "unknown"
      image = "svg/vendor-#{vendor}.svg"
    elsif db == "Host"
      host = @targets_hash[@id] if @targets_hash
      vendor = host ? host.vmm_vendor_display.downcase : "unknown"
      image = "svg/vendor-#{vendor}.svg"
    elsif db == "MiqAction"
      action = @targets_hash[row['id']]
      icon = action ? action.decorate.fonticon : 'product product-action'
    elsif db == "MiqProvision"
      image = "100/miq_request.png"
    elsif db == "MiqWorker"
      worker = @targets_hash[from_cid(@id)]
      image = "100/processmanager-#{worker.normalized_type}.png"
    elsif db == "ExtManagementSystem"
      ems = @targets_hash[from_cid(@id)]
      image = "svg/vendor-#{ems.image_name}.svg"
    elsif db == "Tenant"
      icon = row['divisible'] ? "pficon pficon-tenant" : "pficon pficon-project"
    else
      image = "100/#{db.underscore}.png"
    end

    if icon
      content_tag(:i, nil, :class => icon, :title => title)
    else
      image_tag(ActionController::Base.helpers.image_path(image), :title => title, :alt => nil)
    end
  end

  def listicon_glyphicon_tag_for_widget(widget)
    case widget.status.downcase
    when 'complete' then 'pficon pficon-ok'
    when 'queued'   then 'fa fa-pause'
    when 'running'  then 'pficon pficon-running'
    when 'error'    then 'pficon pficon-warning-triangle-o'
    end
  end

  def listicon_glyphicon_tag(db, row)
    glyphicon2 = nil
    case db
    when "MiqSchedule"
      glyphicon = "fa fa-clock-o"
    when "MiqReportResult"
      case row['status'].downcase
      when "error"
        glyphicon = "pficon pficon-warning-triangle-o"
      when "finished"
        glyphicon = "pficon pficon-ok"
      when "running"
        glyphicon = "pficon pficon-running"
      when "queued"
        glyphicon = "fa fa-pause"
      else
        glyphicon = "fa fa-arrow-right"
      end
    when "MiqUserRole"
      glyphicon = "product product-role"
    when "MiqWidget"
      case row['content_type'].downcase
      when "chart"
        glyphicon = "fa fa-pie-chart"
      when "menu"
        glyphicon = "fa fa-share-square-o"
      when "report"
        glyphicon = "fa fa-file-text-o"
      when "rss"
        glyphicon = "fa fa-rss"
      end
      # for second icon to show status in widget list
      glyphicon2 = listicon_glyphicon_tag_for_widget(row)
    end

    content_tag(:i, nil, :class => glyphicon) do
      content_tag(:i, nil, :class => glyphicon2) if glyphicon2
    end
  end

  def listicon_tag(db, row)
    if %w(MiqReportResult MiqSchedule MiqUserRole MiqWidget).include?(db)
      listicon_glyphicon_tag(db, row)
    else
      listicon_image_tag(db, row)
    end
  end

  # Wrapper around jquery-rjs' remote_function which adds an extra .html_safe()
  # Remove if merged: https://github.com/amatsuda/jquery-rjs/pull/3
  def remote_function(options)
    super(options).to_str
  end

  attr_reader :big_iframe

  def appliance_name
    MiqServer.my_server.name
  end

  def vmdb_build_info(key)
    case key
    when :version then Vmdb::Appliance.VERSION
    when :build then Vmdb::Appliance.BUILD
    end
  end

  def user_role_name
    User.current_user.miq_user_role_name
  end

  def rbac_common_feature_for_buttons(pressed)
    # return feature that should be checked for the button that came in
    case pressed
    when "rbac_project_add", "rbac_tenant_add"
      "rbac_tenant_add"
    else
      pressed
    end
  end

  def action_url_for_views
    if @lastaction == "scan_history"
      "scan_history"
    elsif %w(all_jobs jobs ui_jobs all_ui_jobs).include?(@lastaction)
      "jobs"
    else
      @lastaction && @lastaction != "get_node_info" ? @lastaction : "show_list"
    end
  end

  def route_exists?(hash)
    begin
      url_for_only_path(hash)
    rescue
      return false
    end
    true
  end

  def translate_header_text(text)
    if text == "Region"
      I18n.t("product.name") + " " + _(text)
    else
     _(text)
    end
  end

  def parse_nodetype_and_id(x_node)
    x_node.split('_').last.split('-')
  end
end
