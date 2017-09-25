module Bosh::Spec
  class NewDeployments
    DEFAULT_DEPLOYMENT_NAME = 'simple'

    def self.simple_cloud_config
      minimal_cloud_config.merge({
        'networks' => [network],
        'vm_types' => [vm_type]
      })
    end

    def self.minimal_cloud_config
      {
        'networks' => [{
          'name' => 'a',
          'subnets' => [],
        }],

        'compilation' => {
          'workers' => 1,
          'network' => 'a',
          'cloud_properties' => {},
        },

        'vm_types' => [],
      }
    end

    def self.network(options = {})
      {
        'name' => 'a',
        'subnets' => [subnet],
      }.merge!(options)
    end

    def self.subnet(options = {})
      {
        'range' => '192.168.1.0/24',
        'gateway' => '192.168.1.1',
        'dns' => ['192.168.1.1', '192.168.1.2'],
        'static' => ['192.168.1.10'],
        'reserved' => [],
        'cloud_properties' => {},
      }.merge!(options)
    end

    def self.vm_type
      {
        'name' => 'a',
        'cloud_properties' => {}
      }
    end

    def self.simple_errand_job
      {
        'name' => 'fake-errand-name',
        'templates' => [
          {
            'release' => 'bosh-release',
            'name' => 'errand1'
          }
        ],
        'stemcell' => 'default',
        'lifecycle' => 'errand',
        'vm_type' => 'a',
        'instances' => 1,
        'networks' => [{'name' => 'a'}],
        'properties' => {
          'errand1' => {
            'exit_code' => 0,
            'stdout' => 'fake-errand-stdout',
            'stderr' => 'fake-errand-stderr',
            'run_package_file' => true,
          },
        },
      }
    end
    def self.simple_job(opts = {})
      job_hash = {
        'name' => opts.fetch(:name, 'foobar'),
        'templates' => opts[:templates] || opts[:jobs] || ['name' => 'foobar'],
        'stemcell' => opts[:stemcell] || 'default',
        'vm_type' => opts.fetch(:vm_type, 'a'),
        'instances' => opts.fetch(:instances, 3),
        'networks' => [{ 'name' => opts.fetch(:network_name, 'a') }],
        'properties' => {},
      }

      if opts.has_key?(:static_ips)
        job_hash['networks'].first['static_ips'] = opts[:static_ips]
      end

      if opts[:persistent_disk_pool]
        job_hash['persistent_disk_pool'] = opts[:persistent_disk_pool]
      end

      if opts.has_key?(:azs)
        job_hash['azs'] = opts[:azs]
      end

      if opts.has_key?(:properties)
        job_hash['properties'] = opts[:properties]
      end

      job_hash
    end
    def self.simple_instance_group(opts = {})
      instance_group_hash = {
        'name' => opts.fetch(:name, 'foobar'),
        'stemcell' => opts[:stemcell] || 'default',
        'vm_type' => opts.fetch(:vm_type, 'a'),
        'instances' => opts.fetch(:instances, 3),
        'networks' => [{ 'name' => opts.fetch(:network_name, 'a') }],
        'properties' => {},
        'jobs' => opts.fetch(:jobs, [{
           'name' => opts.fetch(:name, 'foobar'),
           'release' => 'bosh-release',
           'properties' => {}
          }])
      }

      if opts.has_key?(:static_ips)
        instance_group_hash['networks'].first['static_ips'] = opts[:static_ips]
      end

      if opts.has_key?(:azs)
        instance_group_hash['azs'] = opts[:azs]
      end

      if opts.has_key?(:properties)
        instance_group_hash['properties'] = opts[:properties]
      end

      instance_group_hash
    end
    def self.minimal_manifest
      {
        'name' => 'minimal',
        'director_uuid'  => 'deadbeef',

        'releases' => [{
          'name'    => 'test_release',
          'version' => '1' # It's our dummy valid release from spec/assets/test_release.tgz
        }],

        'stemcells' => [{
          'alias' => 'default',
          'os' => 'ubuntu-trusty',
        }],

        'update' => {
          'canaries'          => 2,
          'canary_watch_time' => 4000,
          'max_in_flight'     => 1,
          'update_watch_time' => 20
        }
      }
    end

    def self.minimal_manifest_with_stemcell
      {
        'name' => 'minimal',
        'director_uuid'  => 'deadbeef',

        'releases' => [{
          'name'    => 'test_release',
          'version' => '1' # It's our dummy valid release from spec/assets/test_release.tgz
        }],

        'stemcells' => [{
          'name' => 'ubuntu-stemcell',
          'version' => '1',
          'alias' => 'default'
        }],

        'update' => {
          'canaries'          => 2,
          'canary_watch_time' => 4000,
          'max_in_flight'     => 1,
          'update_watch_time' => 20
        }
      }
    end

    def self.test_release_manifest
      minimal_manifest.merge(
        'name' => DEFAULT_DEPLOYMENT_NAME,

        'releases' => [{
          'name'    => 'bosh-release',
          'version' => '0.1-dev',
        }]
      )
    end

    def self.test_release_manifest_with_stemcell
      minimal_manifest_with_stemcell.merge(
        'name' => DEFAULT_DEPLOYMENT_NAME,

        'releases' => [{
          'name'    => 'bosh-release',
          'version' => '0.1-dev',
        }]
      )
    end

    def self.simple_manifest
      test_release_manifest.merge({
        'jobs' => [simple_job]
      })
    end

    def self.simple_manifest_with_stemcell
      test_release_manifest_with_stemcell.merge({
        'jobs' => [simple_job]
      })
    end

    def self.simple_manifest_with_instance_groups
      test_release_manifest_with_stemcell.merge({
        'instance_groups' => [simple_instance_group]
      })
    end

    def self.manifest_with_errand
      manifest = simple_manifest.merge('name' => 'errand')
      manifest['jobs'].find { |job| job['name'] == 'foobar'}['instances'] = 1
      manifest['jobs'] << simple_errand_job
      manifest
    end

  end
end
