require 'jekyll'
require 'rubygems'
require "google/analytics/data"
require 'chronic'

module Jekyll

  class GoogleAnalytics < Generator
    safe :true
    priority :high

    def generate(site)
      if !site.config['page-view']
        return
      end

      pv = site.config['page-view']

      if !pv['credential']
        puts "page-view warning: set page-view.credential"
        return
      end
      if !pv['property_id']
        puts "page-view warning: set page-view.property_id"
        return
      end
      pv['start'] = pv['start']||'30daysAgo'
      pv['end'] = pv['end']||'now'

      if pv['start'].is_a? String
        pv['start'] = [pv['start']]
      end
      if pv['end'].is_a? String
        pv['end'] = [pv['end']]
      end
      if pv['end'].size < pv['start'].size
        for i in (pv['end'].size)..(pv['start'].size-1)
          pv['end'][i] = pv['end'][0]
        end
      end
      pv['name'] = []
      for i in 0..(pv['start'].size-1)
        pv['name'][i] = '_pv_' + pv['start'][i].gsub(' ', '-')+'-to-'+pv['end'][i].gsub(' ','-')
      end

      client = Google::Analytics::Data.analytics_data do |config|
          config.credentials = pv['credential']
      end

      for i in 0..(pv['start'].size-1)
        request = Google::Analytics::Data::V1beta::RunReportRequest.new(
          property: "properties/#{pv["property_id"]}",
          dimensions: [Google::Analytics::Data::V1beta::Dimension.new(name: "pagePath")],
          metrics: [Google::Analytics::Data::V1beta::Metric.new(name: "screenPageViews")],
          date_ranges: [Google::Analytics::Data::V1beta::DateRange.new(start_date: pv['start'][i], end_date: pv['end'][i])]
        )
        response = begin
          client.run_report(request)
        rescue => e
          puts "page-view error: #{e.message}"
          return
        end

        results = {}
        response.rows.each do |row|
          page_path = row.dimension_values.first.value
          views = row.metric_values.first.value
          results[page_path] = views
        end

        site.config[pv['name'][i]] = 0

        (site.posts.docs + site.pages).each { |page|
          root = site.config['root']
          if root =~/(.+)\/$|^\/$/
            root = $1
          end
          if root == nil
            url = page.url
          else
            url = root + page.url
          end
          hits = (results[url])? results[url].to_i : 0
          page.data.merge!(pv['name'][i] => hits)
          site.config[pv['name'][i]] += hits
          if i == 0
            page.data.merge!("_pv" => hits)
          end
        }
      end
    end
  end

  class PageViewTag < Liquid::Tag

    def initialize(name, marker, token)
      @params = Hash[*marker.split(/(?:: *)|(?:, *)/)]
      super
    end

    def render(context)
      site = context.environments.first['site']
      if !site['page-view']
        return ''
      end

      post = context.environments.first['post']
      if post == nil
        post = context.environments.first['page']
        if post == nil
          return ''
        end
      end

      pv = post['_pv']
      if pv == nil
        return ''
      end

      html = begin
        pv.to_s.reverse.gsub(/...(?=.)/, '\&,').reverse + ' hits'
      rescue => e
        ''
      end
      return html
    end #render
  end # PageViewTag
end

Liquid::Template.register_tag('pageview', Jekyll::PageViewTag)
