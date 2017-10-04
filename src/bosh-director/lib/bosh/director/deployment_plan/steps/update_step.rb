module Bosh::Director
  module DeploymentPlan
    module Steps
      class UpdateStep
        def initialize(base_job, deployment_plan, multi_job_updater)
          @base_job = base_job
          @logger = base_job.logger
          @deployment_plan = deployment_plan
          @multi_job_updater = multi_job_updater
        end

        def perform
          begin
            @logger.info('Updating deployment')
            PreCleanupStep.new(@logger, @deployment_plan).perform
            UpdateActiveVmCpisStep.new(@logger, @deployment_plan).perform
            setup_step.perform
            UpdateJobsStep.new(@base_job, @deployment_plan, @multi_job_updater).perform
            UpdateErrandsStep.new(@base_job, @deployment_plan).perform
            @logger.info('Committing updates')
            PersistDeploymentStep.new(@deployment_plan).perform
            @logger.info('Finished updating deployment')
          ensure
            CleanupStemcellReferencesStep.new(@deployment_plan).perform
          end
        end

        private

        def vm_creator
          return @vm_creator if @vm_creator
          template_blob_cache = @deployment_plan.template_blob_cache
          agent_broadcaster = AgentBroadcaster.new
          vm_deleter = Bosh::Director::VmDeleter.new(@logger, false, Config.enable_virtual_delete_vms)
          dns_encoder = LocalDnsEncoderManager.new_encoder_with_updated_index(@deployment_plan.availability_zones.map(&:name))
          disk_manager = DiskManager.new(@logger, template_blob_cache, dns_encoder)
          @vm_creator = Bosh::Director::VmCreator.new(@logger, vm_deleter, disk_manager, template_blob_cache, dns_encoder, agent_broadcaster)
        end

        def setup_step
          local_dns_repo = LocalDnsRepo.new(@logger, Config.root_domain)
          dns_publisher = BlobstoreDnsPublisher.new(
            lambda { App.instance.blobstores.blobstore },
            Config.root_domain,
            AgentBroadcaster.new,
            LocalDnsEncoderManager.create_dns_encoder,
            @logger
          )
          SetupStep.new(@base_job, @deployment_plan, vm_creator, local_dns_repo, dns_publisher)
        end
      end
    end
  end
end
