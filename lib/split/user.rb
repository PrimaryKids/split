require 'forwardable'

module Split
  class User
    extend Forwardable
    def_delegators :@user, :keys, :[], :[]=, :delete
    attr_reader :user

    def initialize(context, adapter=nil)
      @user = adapter || Split::Persistence.adapter.new(context)
    end

    def [](key)
      if Split::Experiment.key_without_version_for_experiment_key(key.to_s) == key.to_s
        #if the key doesn't have version, return one with version
        #this might not be needed anymore
        @user[key_for_experiment_name(key)]
      else
        @user[key]
      end
    end

    def cleanup_old_experiments!
      keys_without_finished(user.keys).each do |key|
        experiment = ExperimentCatalog.find Split::Experiment.key_without_version_for_experiment_key(key)
        if experiment.nil? || experiment.has_winner? || experiment.start_time.nil?
          user.delete key
          user.delete experiment.finished_key(key) if experiment
        end
      end
    end

    def max_experiments_reached?(experiment_key)
      if Split.configuration.allow_multiple_experiments == 'control'
        experiments = active_experiments
        count_control = experiments.count {|k,v| experiment_key =~ /#{k}(?:\:\d+)?/ || v == 'control'}
        experiments.size > count_control
      else
        !Split.configuration.allow_multiple_experiments &&
          keys_without_experiment(user.keys, experiment_key).length > 0
      end
    end

    def cleanup_old_versions!(experiment)
      keys = user.keys.select { |k| k.match(Regexp.new(experiment.name)) }
      keys_without_experiment(keys, experiment.key).each { |key| user.delete(key) }
    end

    def active_experiments
      experiment_pairs = {}
      keys_without_finished(user.keys).each do |key|
        Metric.possible_experiments(Split::Experiment.key_without_version_for_experiment_key(key)).each do |experiment|
          if !experiment.has_winner?
            experiment_pairs[Split::Experiment.key_without_version_for_experiment_key(key)] = user[key]
          end
        end
      end
      experiment_pairs
    end

    def key_for_experiment(experiment)
      #We grab this from the user keys and not from the experiment object because
      #it concerns the version of the experiment that the user was bucketed into
      keys.find { |k| k.match(Regexp.new("^#{experiment.name}"))}
    end

    def version_for_experiment(experiment)
      kfe = key_for_experiment(experiment)
      if kfe
        kfe.split(":").last
      else
        0
      end
    end

    private

    def key_for_experiment_name(experiment_name)
      keys.find { |k| k.match(Regexp.new("^#{experiment_name}"))}
    end

    def keys_without_experiment(keys, experiment_key)
      keys.reject { |k| k.match(Regexp.new("^#{experiment_key}(:finished)?$")) }
    end

    def keys_without_finished(keys)
      keys.reject { |k| k.include?(":finished") }
    end
  end
end
