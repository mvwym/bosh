module Bosh::Director
  module CloudConfig
    class CloudConfigsConsolidator
      include ValidationHelper

      attr_reader :cloud_configs

      def self.create_from_model_ids(cloud_configs_ids)
        new(Bosh::Director::Models::Config.find_by_ids(cloud_configs_ids))
      end

      def initialize(cloud_configs)
        @cloud_configs = cloud_configs || []
        Config.logger.debug("CLOUDCONFIGS: #{@cloud_configs}")
        @variables_interpolator = Bosh::Director::ConfigServer::VariablesInterpolator.new
      end

      def raw_manifest
        @consolidated_raw_manifest ||= merge_manifests
      end

      def have_cloud_configs?
        !@cloud_configs.empty?
      end

      def interpolate_manifest_for_deployment(deployment_name)
        @variables_interpolator.interpolate_cloud_manifest(raw_manifest, deployment_name)
      end

      private

      def merge_manifests
        return {} if @cloud_configs.empty?

        result_hash = {
          'azs' => [],
          'vm_types' => [],
          'disk_types' => [],
          'networks' => [],
          'vm_extensions' => [],
        }

        @cloud_configs.each do |cloud_config|
          manifest_hash = cloud_config.raw_manifest
          result_hash['azs'] += safe_property(manifest_hash, 'azs', :class => Array, :default => [])
          result_hash['vm_types'] += safe_property(manifest_hash, 'vm_types', :class => Array, :default => [])
          result_hash['disk_types'] += safe_property(manifest_hash, 'disk_types', :class => Array, :default => [])
          result_hash['networks'] += safe_property(manifest_hash, 'networks', :class => Array, :default => [])
          result_hash['vm_extensions'] += safe_property(manifest_hash, 'vm_extensions', :class => Array, :default => [])

          compilation = safe_property(manifest_hash, 'compilation', :class => Hash, :optional => true)
          if compilation && result_hash['compilation']
            raise CloudConfigMergeError, "Cloud config 'compilation' key cannot be defined in multiple cloud configs."
          end
          result_hash['compilation'] = compilation unless compilation.nil?
        end

        result_hash
      end

    end
  end
end
