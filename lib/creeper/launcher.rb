$stdout.sync = $stderr.sync = true
$stdin.binmode
$stdout.binmode
$stderr.binmode

require 'creeper'

module Creeper
  module Launcher

    extend self

    def launch!(options)
      $stdin.reopen("/dev/null")

      # grandparent - reads pipe, exits when master is ready
      #  \_ parent  - exits immediately ASAP
      #      \_ creeper master - writes to pipe when ready

      rd, wr = IO.pipe
      grandparent = $$
      if fork
        wr.close # grandparent does not write
      else
        rd.close # creeper master does not read
        Process.setsid
        exit if fork # parent dies now
      end

      if grandparent == $$
        # this will block until Creeper.join runs (or it dies)
        creeper_pid = (rd.readpartial(16) rescue nil).to_i
        unless creeper_pid > 1
          warn "creeper failed to start, check stderr log for details"
          exit!(1)
        end
        exit 0
      else # creeper master process
        options[:ready_pipe] = wr
      end
    end

  end
end