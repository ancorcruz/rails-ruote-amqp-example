AMQP.settings[:host] = Settings.amqp.host
# make changes when needed
#
# you may use another persistent storage for example or include a worker so that
# you don't have to run it in a separate instance
#
# See http://ruote.rubyforge.org/configuration.html for configuration options of
# ruote.

require 'ruote/storage/fs_storage'
require 'ruote-redis'
require 'redis'

#RUOTE_STORAGE = Ruote::FsStorage.new("ruote_work_#{Rails.env}")
RUOTE_STORAGE = Ruote::Redis::Storage.new(Redis.new( {
  :db => "ruote_work_#{Rails.env}",
  :thread_safe => true,
  :host => Settings.redis.host,
  :port => Settings.redis.port
}), {})

RuoteKit.engine = Ruote::Engine.new(RUOTE_STORAGE)
#RuoteKit.engine = Ruote::Engine.new(Ruote::Worker.new(RUOTE_STORAGE))
# By default, there is a running worker when you start the Rails server. That is
# convenient in development, but may be (or not) a problem in deployment.
#
# Please keep in mind that there should always be a running worker or schedules
# may get triggered to late. Some deployments (like Passenger) won't guarantee
# the Rails server process is running all the time, so that there's no always-on
# worker. Also beware that the Ruote::HashStorage only supports one worker.
#
# If you don't want to start a worker thread within your Rails server process,
# replace the line before this comment with the following:
#
# RuoteKit.engine = Ruote::Engine.new(RUOTE_STORAGE)
#
# To run a worker in its own process, there's a rake task available:
#
#     rake ruote:run_worker
#
# Stop the task by pressing Ctrl+C

unless Rails.env == 'production'
  RuoteKit.engine.storage.clear
end

if $RAKE_TASK
  # listen to the ruote_workitems queue for return-messages
  RuoteAMQP::Receiver.new(RuoteKit.engine) #, :launchitems => false)
else # don't register participants in rake tasks
  RuoteKit.engine.register do
    participant :ldap, RuoteAMQP::ParticipantProxy, :queue => "ldap_job" do
      puts "!!!! #{workitem}"
    end

    participant :email, RuoteAMQP::ParticipantProxy, :queue => "email_job"
    participant :notifier, RuoteAMQP::ParticipantProxy, :queue => "notify_job", :forget => true
    #participant :editor

    # register the catchall storage participant named '.+'
    catchall

    participant :logger do |workitem|
      STDOUT.puts "log workitem: #{workitem.fields.inspect}"
      #STDERR.puts "State: #{workitem.fields['state']}"
      #STDERR.puts "Count: #{workitem.fields['count']}"
    end

    # register your own participants using the participant method
    #
    # Example: participant 'alice', Ruote::StorageParticipant see
    # http://ruote.rubyforge.org/participants.html for more info

    # register the catchall storage participant named '.+'
    #catchall
  end

  PDEF_AMPQ = Ruote.process_definition do
    repeat do
      ldap
      logger
      email
      logger
      notifier
      logger
    end
  end

  RuoteKit.engine.launch(PDEF_AMPQ)
end

# when true, the engine will be very noisy (stdout)
#
RuoteKit.engine.context.logger.noisy = true


# test process definition

play_pingpong = false
if play_pingpong
  class Opponent
    include Ruote::LocalParticipant

    def initialize (options)
      @options = options
    end

    def consume (workitem)
      puts @options['sound'].green
      workitem.fields['i'] ||= 0
      workitem.fields['i'] += 1
      puts workitem.inspect.white
      #puts Businesspartner.last.inspect
      reply_to_engine(workitem)
    end

  end

  unless IS_RAKE_TASK
    puts "!!! playing ping poing !!!".white
    RuoteKit.engine.register do 
      participant :ping, Opponent, 'sound' => 'ping'
      participant :pong, Opponent, 'sound' => 'pong'
    end

    PDEF_PINGPONG = Ruote.process_definition do
      cursor do
        repeat do
          ping  :task=>'play game!!!'  # mister ping, please shoot first
          pong
          _break :if => '${f:i} >= ${f:rounds}'
        end
      end
    end

    wfid = RuoteKit.engine.launch(PDEF_PINGPONG, :rounds=>3)
  end

#sleep 2 # five seconds of ping pong fun
#RuoteKit.engine.cancel_process(wfid) # game over

end

