require 'sinatra'
require 'active_support'
require 'active_record'
require 'delayed_job'
require 'haml'

class DelayedJobWeb < Sinatra::Base
  set :root, File.dirname(__FILE__)
  set :static, true
  set :public_folder,  File.expand_path('../public', __FILE__)
  set :views,  File.expand_path('../views', __FILE__)
  set :haml, { :format => :html5 }

  def current_page
    url_path request.path_info.sub('/','')
  end

  def start
    params[:start].to_i
  end

  def per_page
    4
  end

  def url_path(*path_parts)
    [ path_prefix, path_parts ].join("/").squeeze('/')
  end
  alias_method :u, :url_path

  def path_prefix
    request.env['SCRIPT_NAME']
  end

  def tabs
    [
      {:name => 'Overview', :path => '/overview'},
      {:name => 'Enqueued', :path => '/enqueued'},
      {:name => 'Working', :path => '/working'},
      {:name => 'Pending', :path => '/pending'},
      {:name => 'Failed', :path => '/failed'},
      {:name => 'Stats', :path => '/stats'}
    ]
  end


  def backend
    delayed_job.name.match(/mongoid/i).present? ? :mongoid : :active_record
  end
  
  def delayed_job
    begin
      Delayed::Job
    rescue
      false
    end
  end

  get '/overview' do
    if delayed_job
      haml :overview
    else
      @message = "Unable to connected to Delayed::Job database"
      haml :error
    end
  end

  get '/stats' do
    haml :stats
  end

  %w(enqueued working pending failed).each do |page|
    get "/#{page}" do
      if backend == :mongoid
        @jobs = delayed_jobs(page.to_sym).order_by(:created_at.desc).skip(start).limit(per_page)
      else
        @jobs = delayed_jobs(page.to_sym).order('created_at desc').offset(start).limit(per_page)
      end
      @all_jobs = delayed_jobs(page.to_sym)
      haml page.to_sym
    end
  end

  get "/remove/:id" do
    delayed_job.find(params[:id]).delete
    redirect back
  end

  get "/requeue/:id" do
    job = delayed_job.find(params[:id])
    job.run_at = Time.now
    job.save
    redirect back
  end

  post "/failed/clear" do
    delayed_jobs(:failed).delete_all
    redirect u('failed')
  end

  post "/requeue/all" do
    delayed_jobs(:failed).each{|dj| dj.run_at = Time.now; dj.save}
    redirect back
  end

  def delayed_jobs(type)
    if backend == :mongoid
      criteria_for(type)
    else
      delayed_job.where(delayed_job_sql(type))
    end
  end

  def criteria_for(type)
    case type
    when :enqueued
      delayed_job.all
    when :working
      delayed_job.where(:locked_at.exists => true)
    when :failed
      delayed_job.where(:last_error.exists => true)
    when :pending
      delayed_job.where(:attempts => 0)
    end
  end
  
  def delayed_job_sql(type)
    case type
    when :enqueued
      ''
    when :working
      'locked_at is not null'
    when :failed
      'last_error is not null'
    when :pending
      'attempts = 0'
    end
  end

  get "/?" do
    redirect u(:overview)
  end

  def partial(template, local_vars = {})
    @partial = true
    haml(template.to_sym, {:layout => false}, local_vars)
  ensure
    @partial = false
  end

  %w(overview enqueued working pending failed stats) .each do |page|
    get "/#{page}.poll" do
      show_for_polling(page)
    end

    get "/#{page}/:id.poll" do
      show_for_polling(page)
    end
  end

  def poll
    if @polling
      text = "Last Updated: #{Time.now.strftime("%H:%M:%S")}"
    else
      text = "<a href='#{u(request.path_info)}.poll' rel='poll'>Live Poll</a>"
    end
    "<p class='poll'>#{text}</p>"
  end

  def show_for_polling(page)
    content_type "text/html"
    @polling = true
    # show(page.to_sym, false).gsub(/\s{1,}/, ' ')
    @jobs = delayed_jobs(page.to_sym)
    haml(page.to_sym, {:layout => false})
  end

end

# Run the app!
#
# puts "Hello, you're running delayed_job_web"
# DelayedJobWeb.run!
