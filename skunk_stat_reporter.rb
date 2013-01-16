# Author:: Branden Faulls <skunk_stats_injector@clockworkrobot.co.uk>
# 
# Copyright (c) 2012 Branden Faulls, http://www.clockworkrobot.co.uk/
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module SkunkStatReporter

  require 'xmlrpc/client'
  require 'sequel'

  def self.build (&block)
    reporter = Reporter.new()
    reporter.instance_eval &block

    reporter.render
  end


  class Reporter

    def initialize()
      @database = Database.new()
      @wiki = ConfluenceWiki.new()
      @reports = []
    end

    #db abstractions
    def db_name(name)
      @database.name = name
    end

    def db_username(username)
      @database.username = username
    end

    def db_password(password)
      @database.password = password
    end

    def db_host(host)
      @database.host = host
    end

    #wiki abstractions

    def wiki_url(url)
      @wiki.url = url
    end

    def wiki_username(username)
      @wiki.username = username
    end

    def wiki_password(password)
      @wiki.password = password
    end

    #report building

    def report(title, &block)
      report = Report.new(title, @database)
      report.instance_eval(&block)

      @reports << report
    end

    def render()
      @reports.each do |report|
        @wiki.publish(report.title, report.parent, report.space_name, report.render)
      end
    end

  end



  class ConfluenceWiki
    attr_accessor :url, :username, :password

    def build_client()
      # Log in to Confluence
      @client = XMLRPC::Client.new_from_uri(@url).proxy("confluence1")
      @client.instance_variable_get("@server").instance_variable_get("@http").verify_mode = OpenSSL::SSL::VERIFY_NONE
      @token = @client.login(@username, @password)
    end

    def publish(title,parent, space, content)
      build_client

      parent_page  = @client.getPage(@token, space, parent)


      begin
        page = @client.getPage(@token, space, title)
      rescue XMLRPC::FaultException => e
        if (e.faultString.include?("java.lang.Exception: com.atlassian.confluence.rpc.RemoteException: You're not allowed to view that page, or it does not exist."))
          page = {
            :space => space,
            :title => title,
            :parentId => parent_page['id']
          }
        else
          raise e.faultString
        end
      end


      page['content'] = content

      @client.storePage(@token, page)
      @client.logout(@token)
    end
  end

  class Database
    attr_accessor :name, :host, :username, :password


    def query( sql )
      db = Sequel.connect(
                  :adapter => 'mysql',
                  :user => @username,
                  :host => @host,
                  :database => @name,
                  :password => @password
                  )

      return db.fetch(sql)
    end

  end


  class Report
    attr_reader :title, :columns, :headers, :query, :space_name, :chart_config, :db, :parent

    def initialize(title, db)
      @title = title
      @db = db
      @columns = []
      @headers = []
      @chart_config = {}

    end

    def query(query)
      @query = query
    end

    def space(space)
      @space_name = space
    end

    def parent_page(parent)
      @parent = parent
    end

    def table_headers(*headers)
      @headers = headers
    end

    def chart_type(type)
      @chart_type = type
    end



    def chart(&block)
      self.instance_eval(&block)
    end

    #chart_config
    def type(chart_type)
      @chart_config['type'] = chart_type
    end

    def date_format(format)
      @chart_config['dateFormat'] = format
    end

    def time_period(period)
      @chart_config['timePeriod'] = period
    end

    def data_orientation(orientation)
      @chart_config['dataOrientation'] = orientation
    end

    def data_display(display)
      @chart_config['dataDisplay'] = display
    end

    def columns(*columns)
      @chart_config['columns'] = columns
    end


    def render()
      output = ''

      chart_params = []
      @chart_config.each do |key, value|
        if value.is_a? Array
          chart_params << "#{key}=#{value.join(',')}"
        elsif value.is_a? String
          chart_params << "#{key}=#{value}"
        else

        end
      end
      output << "{chart:#{chart_params.join('|')}|width=800}\n"
      output << "|| #{@headers.join(' || ')} ||\n"

      @db.query(@query).each do |row|
        output << "| "
        row.values.each do |value|
          if value.is_a? String
            output << value
          elsif value.is_a? Date
            output << value.to_s
          elsif value.is_a? Fixnum
              output << value.to_i.to_s
          elsif value.is_a? BigDecimal
            output << value.to_f.round(3).to_s
          else
            output << value.to_s
          end

          output << " |"
        end

        output << "\n"
      end
      output << "{chart}\n"
      return output
    end
  end
end
