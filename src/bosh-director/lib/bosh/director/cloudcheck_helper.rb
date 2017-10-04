module Bosh::Director
  module CloudcheckHelper
    # Helper functions that come in handy for
    # cloudcheck:
    # 1. VM/agent interactions
    # 2. VM lifecycle operations (from cloudcheck POV)
    # 3. Error handling

    # This timeout has been made pretty short mainly
    # to avoid long cloudchecks, however 10 seconds should
    # still be pretty generous interval for agent to respond.
    DEFAULT_AGENT_TIMEOUT = 10

    def reboot_vm(instance)
      vm = instance.active_vm

      cloud = CloudFactory.create_from_deployment(instance.deployment).get(vm.cpi)
      cloud.reboot_vm(vm.cid)

      begin
        agent_client(instance.agent_id).wait_until_ready
      rescue Bosh::Director::RpcTimeout
        handler_error('Agent still unresponsive after reboot')
      rescue Bosh::Director::TaskCancelled
        handler_error('Task was cancelled')
      end
    end

    def delete_vm(instance)
      # Paranoia: don't blindly delete VMs with persistent disk
      disk_list = agent_timeout_guard(instance.vm_cid, instance.agent_id) do |agent|
        agent.list_disk
      end

      if disk_list.size != 0
        handler_error('VM has persistent disk attached')
      end

      vm_deleter.delete_for_instance(instance)
    end

    def delete_vm_reference(instance)
      vm_model = instance.active_vm
      instance.active_vm = nil
      if vm_model != nil
        vm_model.delete
      end
    end

    def delete_vm_from_cloud(instance_model)
      @logger.debug("Deleting Vm: #{instance_model})")

      validate_spec(instance_model.spec)
      validate_env(instance_model.vm_env)

      vm_deleter.delete_for_instance(instance_model)
    end

    def recreate_vm_skip_post_start(instance_model)
      recreate_vm(instance_model, false)
    end

    def recreate_vm(instance_model, run_post_start = true)
      @logger.debug("Recreating Vm: #{instance_model})")
      delete_vm_from_cloud(instance_model)

      instance_plan_to_create = create_instance_plan(instance_model)

      Bosh::Director::Core::Templates::TemplateBlobCache.with_fresh_cache do |template_cache|
        dns_encoder = LocalDnsEncoderManager.create_dns_encoder
        vm_creator(template_cache, dns_encoder).create_for_instance_plan(
          instance_plan_to_create,
          Array(instance_model.managed_persistent_disk_cid),
          instance_plan_to_create.tags,
          true
        )

        powerdns_manager = PowerDnsManagerProvider.create
        local_dns_manager = LocalDnsManager.create(Config.root_domain, @logger)
        dns_names_to_ip = {}

        root_domain = Config.root_domain

        apply_spec = instance_plan_to_create.existing_instance.spec
        apply_spec['networks'].each do |network_name, network|
          index_dns_name = Bosh::Director::DnsNameGenerator.dns_record_name(
            instance_model.index,
            instance_model.job,
            network_name,
            instance_model.deployment.name,
            root_domain,
          )
          dns_names_to_ip[index_dns_name] = network['ip']

          id_dns_name = Bosh::Director::DnsNameGenerator.dns_record_name(
            instance_model.uuid,
            instance_model.job,
            network_name,
            instance_model.deployment.name,
            root_domain,
          )
          dns_names_to_ip[id_dns_name] = network['ip']
        end

        @logger.debug("Updating DNS record for instance: #{instance_model.inspect}; to: #{dns_names_to_ip.inspect}")
        powerdns_manager.update_dns_record_for_instance(instance_model, dns_names_to_ip)
        local_dns_manager.update_dns_record_for_instance(instance_model)

        powerdns_manager.flush_dns_cache

        cloud_check_procedure = lambda do
          blobstore_client = App.instance.blobstores.blobstore

          cleaner = RenderedJobTemplatesCleaner.new(instance_model, blobstore_client, @logger)
          templates_persister = RenderedTemplatesPersister.new(blobstore_client, @logger)

          templates_persister.persist(instance_plan_to_create)

          # for backwards compatibility with instances that don't have update config
          update_config = apply_spec['update'].nil? ? nil : DeploymentPlan::UpdateConfig.new(apply_spec['update'])

          InstanceUpdater::StateApplier.new(
            instance_plan_to_create,
            agent_client(instance_model.agent_id),
            cleaner,
            @logger,
            {}
          ).apply(update_config, run_post_start)
        end
        InstanceUpdater::InstanceState.with_instance_update(instance_model, &cloud_check_procedure)
      end
    end

    private

    def create_instance_plan(instance_model)
      env = DeploymentPlan::Env.new(instance_model.vm_env)
      stemcell = DeploymentPlan::Stemcell.parse(instance_model.spec['stemcell'])
      stemcell.add_stemcell_models
      stemcell.deployment_model = instance_model.deployment
      # FIXME cpi is not passed here (otherwise, we would need to parse the CPI using the cloud config & cloud manifest parser)
      # it is not a problem, since all interactions with cpi go over cloud factory (which uses only az name)
      # but still, it is ugly and dangerous...
      availability_zone = DeploymentPlan::AvailabilityZone.new(instance_model.availability_zone,
        instance_model.cloud_properties_hash,
        nil)

      instance_from_model = DeploymentPlan::Instance.new(
        instance_model.job,
        instance_model.index,
        instance_model.state,
        instance_model.cloud_properties_hash,
        stemcell,
        env,
        false,
        instance_model.deployment,
        instance_model.spec,
        availability_zone,
        @logger
      )
      instance_from_model.bind_existing_instance_model(instance_model)

      DeploymentPlan::ResurrectionInstancePlan.new(
        existing_instance: instance_model,
        instance: instance_from_model,
        desired_instance: DeploymentPlan::DesiredInstance.new,
        recreate_deployment: true,
        tags: instance_from_model.deployment_model.tags
      )
    end

    def handler_error(message)
      raise Bosh::Director::ProblemHandlerError, message
    end

    def agent_client(agent_id, timeout = DEFAULT_AGENT_TIMEOUT, retries = 0)
      options = {
        :timeout => timeout,
        :retry_methods => {:get_state => retries}
      }
      @clients ||= {}
      @clients[agent_id] ||= AgentClient.with_agent_id(agent_id, options)
    end

    def agent_timeout_guard(vm_cid, agent_id, &block)
      yield agent_client(agent_id)
    rescue Bosh::Director::RpcTimeout
      handler_error("VM '#{vm_cid}' is not responding")
    end

    def vm_deleter
      @vm_deleter ||= VmDeleter.new(@logger, false, Config.enable_virtual_delete_vms)
    end

    def vm_creator(template_cache, dns_encoder)
      disk_manager = DiskManager.new(@logger, template_cache, dns_encoder)
      agent_broadcaster = AgentBroadcaster.new
      @vm_creator ||= VmCreator.new(@logger, vm_deleter, disk_manager, template_cache, dns_encoder, agent_broadcaster)
    end

    def validate_spec(spec)
      handler_error('Unable to look up VM apply spec') unless spec

      unless spec.kind_of?(Hash)
        handler_error('Invalid apply spec format')
      end
    end

    def validate_env(env)
      unless env.kind_of?(Hash)
        handler_error('Invalid VM environment format')
      end
    end

    def generate_agent_id
      SecureRandom.uuid
    end
  end
end
