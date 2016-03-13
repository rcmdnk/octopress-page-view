require 'jekyll'
require 'jekyll/post'
require 'rubygems'
require 'google/apis/analytics_v3'
require 'google/api_client/auth/key_utils'
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

      if !pv['key_file']
        return
      end
      pv['key_file'] = pv['key_file']
      pv['key_secret'] = pv['key_secret']||'notasecret'
      pv['start'] = pv['start']||'1 month ago'
      pv['end'] = pv['end']||'now'
      pv['metric'] = pv['metric']||'ga:pageviews'
      pv['segment'] = pv['segment']||'gaid::-1'
      pv['filters'] = pv['filters']||nil

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

      # Analytics service
      service = Google::Apis::AnalyticsV3::AnalyticsService.new

      # Load our credentials for the service account
      key = Google::APIClient::KeyUtils.load_from_pkcs12(pv['key_file'], pv['key_secret'])
      service.authorization = Signet::OAuth2::Client.new(
        :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
        :audience => 'https://accounts.google.com/o/oauth2/token',
        :scope=> Google::Apis::AnalyticsV3::AUTH_ANALYTICS_READONLY,
        :issuer => pv['service_account_email'],
        :signing_key => key)

      # Request a token for our service account
      service.authorization.fetch_access_token!

      for i in 0..(pv['start'].size-1)
        response = service.get_ga_data(
          pv['profileID'],
          Chronic.parse(pv['start'][i]).strftime("%Y-%m-%d"),
          Chronic.parse(pv['end'][i]).strftime("%Y-%m-%d"),
          pv['metric'],
          dimensions: "ga:pagePath",
          max_results: 100000,
          segment: pv['segment'],
          filters: pv['filters']
        )
        results = Hash[response.rows]

        site.config[pv['name'][i]] = 0

        (site.posts + site.pages).each { |page|
          url = (site.config['baseurl'] || '') + page.url
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

      html = pv.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse + ' hits'
      return html
    end #render
  end # PageViewTag
end

Liquid::Template.register_tag('pageview', Jekyll::PageViewTag)
