# frozen_string_literal: true
module Split
  class Alternative
    attr_accessor :name
    attr_accessor :experiment_name
    attr_accessor :weight
    attr_accessor :recorded_info
    attr_accessor :version

    def initialize(name, experiment_name, version = 0)
      @experiment_name = experiment_name
      if Hash === name
        @name = name.keys.first
        @weight = name.values.first
      else
        @name = name
        @weight = 1
      end

      @version = version

      p_winner = 0.0
    end

    def to_s
      name
    end

    def goals
      self.experiment.goals
    end

    def p_winner(goal = nil)
      field = set_prob_field(goal)
      @p_winner = Split.redis.hget(key, field).to_f
    end

    def set_p_winner(prob, goal = nil)
      field = set_prob_field(goal)
      Split.redis.hset(key, field, prob.to_f)
    end

    def participant_count(version_key = version)
      Split.redis.hget(key(version_key), 'participant_count').to_i
    end

    def participant_counts
      (0..version).map do |i|
        participant_count(i)
      end
    end

    def participant_count=(count)
      Split.redis.hset(key, 'participant_count', count.to_i)
    end

    def completed_count(goal = nil, version_key = version)
      field = set_field(goal)
      Split.redis.hget(key(version_key), field).to_i
    end

    def completed_counts(goal = nil)
      (0..version).map do |i|
        completed_count(goal, i)
      end
    end

    def all_completed_count(version_key = version)
      if goals.empty?
        completed_count
      else
        goals.inject(completed_count) do |sum, g|
          sum + completed_count(g, version_key)
        end
      end
    end

    def all_completed_counts
      (0..version).map do |i|
        all_completed_count(i)
      end
    end

    def unfinished_count(version_key = version)
      participant_count(version_key) - all_completed_count(version_key)
    end

    def unfinished_counts
      (0..version).map do |i|
        unfinished_count(i)
      end
    end

    def set_field(goal)
      field = "completed_count"
      field += ":" + goal unless goal.nil?
      return field
    end

    def set_prob_field(goal)
      field = "p_winner"
      field += ":" + goal unless goal.nil?
      return field
    end

    def set_completed_count (count, goal = nil)
      field = set_field(goal)
      Split.redis.hset(key, field, count.to_i)
    end

    def increment_participation
      Split.redis.hincrby key, 'participant_count', 1
    end

    def increment_completion(goal = nil)
      field = set_field(goal)
      Split.redis.hincrby(key, field, 1)
    end

    def control?
      experiment.control.name == self.name
    end

    def conversion_rate(goal = nil)
      return 0 if participant_count.zero?
      (completed_count(goal).to_f)/participant_count.to_f
    end

    def experiment
      Split::ExperimentCatalog.find(experiment_name)
    end

    def z_score(goal = nil)
      # p_a = Pa = proportion of users who converted within the experiment split (conversion rate)
      # p_c = Pc = proportion of users who converted within the control split (conversion rate)
      # n_a = Na = the number of impressions within the experiment split
      # n_c = Nc = the number of impressions within the control split

      control = experiment.control
      alternative = self

      return 'N/A' if control.name == alternative.name

      p_a = alternative.conversion_rate(goal)
      p_c = control.conversion_rate(goal)

      n_a = alternative.participant_count
      n_c = control.participant_count

      z_score = Split::Zscore.calculate(p_a, n_a, p_c, n_c)
    end

    def extra_info
      data = Split.redis.hget(key, 'recorded_info')
      if data && data.length > 1
        begin
          JSON.parse(data)
        rescue
          {}
        end
      else
        {}
      end
    end

    def record_extra_info(k, value = 1)
      @recorded_info = self.extra_info || {}

      if value.kind_of?(Numeric)
        @recorded_info[k] ||= 0
        @recorded_info[k] += value
      else
        @recorded_info[k] = value
      end

      Split.redis.hset key, 'recorded_info', (@recorded_info || {}).to_json
    end

    def save
      Split.redis.hsetnx key, 'participant_count', 0
      Split.redis.hsetnx key, 'completed_count', 0
      Split.redis.hsetnx key, 'p_winner', p_winner
      Split.redis.hsetnx key, 'recorded_info', (@recorded_info || {}).to_json
    end

    def validate!
      unless String === @name || hash_with_correct_values?(@name)
        raise ArgumentError, 'Alternative must be a string'
      end
    end

    def reset
      Split.redis.hmset key, 'participant_count', 0, 'completed_count', 0, 'recorded_info', nil
      unless goals.empty?
        goals.each do |g|
          field = "completed_count:#{g}"
          Split.redis.hset key, field, 0
        end
      end
    end

    def delete
      Split.redis.del(key)
    end

    private

    def hash_with_correct_values?(name)
      Hash === name && String === name.keys.first && Float(name.values.first) rescue false
    end

    def key(version_key = @version)
      "#{experiment_name}:version_#{version_key}:#{name}"
    end
  end
end
