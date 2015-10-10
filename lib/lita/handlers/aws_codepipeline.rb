require 'aws-sdk'

module Lita
  module Handlers
    class AwsCodepipeline < Handler
      config :action_category, type: String, required: true
      config :action_provider, type: String, required: true
      config :action_version, type: String, required: true
      # Using ENV for now
      # config :access_key, type: String
      # config :secret_key, type: String

      route(/^aws test/) do |response|
        begin
          codepipeline_client
          actions = @codepipeline_client.list_action_types
        rescue Aws::CodePipeline::Errors => e
          log.debug 'Failed to retrieved CodePipeline Actions' + e
          response.reply 'Failed to retrieved CodePipeline Actions' + e
        end

        custom_action = find_action(config.action_provider,config.action_category,config.action_version)
        if custom_action.empty?
          log.debug('Cannot find custom action : ' + config.action_provider)
          response.reply('Cannot find custom action : ' + config.action_provider)
        else
          log.debug('Found custom action type :' + custom_action.first.id.provider)
          response.reply('Found custom action type :' + custom_action.first.id.provider)
        end
      end

      route(/^aws monitor/) do | response |
        codepipeline_client
        unless find_action(config.action_provider,config.action_category,config.action_version).empty?
          log.debug('Found custom action type' + config.action_provider + "\n" +
                    'Starting to monitor for jobs')
          every(5) do |timer|
            log.debug('Polling jobs')
            job = poll_job
            log.debug('Job polling result: ' + job.inspect)
            unless job.jobs.empty?
              log.debug('Found job waiting for Approval: ' + job.jobs.first['id'])
              ack_job(job.jobs.first['id'], job.jobs.first['nonce'])
              response.reply('Deployment ' + "#{job.jobs.first.data.input_artifacts.first.name}(#{job.jobs.first['id']}) is ready\n" +
                'Release this version by typying' + "\n" +
                "`lita aws deploy #{job.jobs.first['id']}`")
            end
            log.debug('Nothing to do with the previous job polling result')
          end
        end
      end

      route(/^aws deploy\s+(.+)/) do |response|
        log.debug('Deploying ' + response.matches[0][0])
        deploy(response.matches[0][0])
        response.reply("Deployment in progress")
      end

      def deploy(jobid)
        codepipeline_client
        log.debug('Sending job success to ' + jobid)
        @codepipeline_client.put_job_success_result({
          job_id: jobid,
          current_revision: {
            revision: '666', # required
            change_identifier: "RevisionChangeIdentifier"
          }
        })
      end

      def poll_job
        job_result = @codepipeline_client.poll_for_jobs({
          action_type_id: {
            category: config.action_category, # required, accepts Source, Build, Deploy, Test, Invoke
            owner: "Custom", # required, accepts AWS, ThirdParty, Custom
            provider: config.action_provider, # required
            version: config.action_version, # required
          },
        })
        log.debug('Job polling result: ' + job_result.inspect)
        job_result
      end

      def ack_job(jobid, jobnonce)
        log.debug('Acking job: ' + jobid)
        @codepipeline_client.acknowledge_job({
          job_id: jobid,
          nonce: jobnonce
        })
      end

      def find_action(provider,category, version, owner = 'Custom')
        actions = @codepipeline_client.list_action_types
        actions.action_types.select do |action|
          action.id.provider == provider &&
          action.id.owner == owner &&
          action.id.category == category &&
          action.id.version == version
        end
      end

      def codepipeline_client
        @codepipeline_client ||= Aws::CodePipeline::Client.new(region: 'us-east-1')
      end

      Lita.register_handler(self)
    end
  end
end
