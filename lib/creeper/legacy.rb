module Creeper
  module Legacy

    def job_descriptions
      @job_descriptions ||= {}
    end

    def enqueue(job, *args)
      enqueue!(job, *args)
    end

    def enqueue!(job, *args)
      options     = args.last.is_a?(Hash) ? args.last : {}
      priority    = options[:priority] || options[:pri] || 65536
      delay       = [ 0, options[:delay].to_i ].max
      time_to_run = options[:time_to_run] || options[:ttr] || 120

      klass = options[:class] || job_descriptions[job]

      Creeper::Client.push({
        'queue'       => job,
        'args'        => args,
        'class'       => klass,
        'delay'       => delay,
        'priority'    => priority,
        'time_to_run' => time_to_run
      })
    end

  end
end