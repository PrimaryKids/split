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
      if key_without_version(key) == key
        #if the key doesn't have version, return one with version
        @user[key_for_experiment_name(key)]
      else
        @user[key]
      end
    end

    def cleanup_old_experiments!
      keys_without_finished(user.keys).each do |key|
        experiment = ExperimentCatalog.find key_without_version(key)
        if experiment.nil? || experiment.has_winner? || experiment.start_time.nil?
          user.delete key
          user.delete experiment.finished_key(key)
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
      user.keys.each do |key|
        Metric.possible_experiments(key_without_version(key)).each do |experiment|
          if !experiment.has_winner?
            experiment_pairs[key_without_version(key)] = user[key]
          end
        end
      end
      experiment_pairs
    end

    def key_for_experiment(experiment)
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

    def key_without_version(key)
      key.split(/\:\d(?!\:)/)[0]
    end
  end
end
