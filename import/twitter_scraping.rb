require './import/tweet_data.rb'
require 'open-uri'

# アカウント名からトップページのhtmlを取得
def get_top_html
  url = "https://twitter.com/#{session[:user][:name]}"
  open(url).read
end

# htmlを与えるとmin-positionを返す
def get_min_position(top_html)
  top_html[/data-min-position="(.+?)"/, 1]
end

# min_positionからjsonを取得，次のmin_positionとhtmlに分割
def get_next_json(min_position)
  url = "https://twitter.com/i/profiles/show/#{session[:user][:name]}/timeline/tweets?include_available_features=1&include_entities=1&max_position=#{min_position}&reset_error_state=false"
  json_data = open(url).read
  
  # 正規表現によりそれぞれを抜き出す
  next_min = json_data[/"min_position":"(.+?)"/, 1]
  next_html = json_data[/"items_html":"(.+?)","new_latent_count"/, 1]

  # htmlの内容が崩れているので修正
  # \" -> "，\/ -> /，改行文字を改行するように再連結
  next_html = next_html.gsub(/\\u([\da-fA-F]{4})/) { [$1].pack('H*').unpack('n*').pack('U*') }
  # 何故かUTF-8で怒られるのでencode
  next_html = next_html.force_encoding('utf-8')
  next_html = next_html.encode("utf-16be", "utf-8", :invalid => :replace, :undef => :replace, :replace => '?').encode("utf-8")

  revised_html = ""
  next_html.split('\n').each do |line|
    revised_html << line.gsub(%r{\\"|\\/}, '\"'=>'"', '\/'=>'/') << "\n"
  end

  {"min_position" => next_min, "html" => revised_html}
end

# htmlからtweet情報を取得
def pull_out_tweet_data(html)
  # tweetのデータが入っているlistを正規表現で切り取り
  tweet_data = html.scan(%r{<li class="js-stream-item stream-item stream-item.+?\n\n</li>\n\n}m)
  tweet_data.each do |data|
    $tweet_data_list << TweetData.new(data)
  end
end

# 取得したtweetデータを表示する
def print_tweets
  $tweet_data_list.each do |tweet_data|
    puts "-"*50
    puts tweet_data.time_and_day
    puts "@" + tweet_data.account + "さんのTweet"
    puts tweet_data.tweet
    puts "-"*50
  end
end

# 第一引数が第二引数より新しい日付or同じ日ならtreu
def is_new_date(date1, date2)
  # date1 = "%04d"%date1[0] + "%02d"%date1[1] + "%02d"%date1[2]
  # date2 = "%04d"%date2[0] + "%02d"%date2[1] + "%02d"%date2[2]
  date1 >= date2
end

# 日付をしていし，そこまでのtweetをtextで保存
def get_tweets_up_to_specified_date(specify_date)
  # tweets_file = File.open("./Tweets/#{session[:user][:name]}", "w")
  top_html = get_top_html
  pull_out_tweet_data(top_html)
  min_position = get_min_position(top_html)

  p "-"*100
  p top_html
  p "-"*100

  get_flag = true
  tweets = []
  if $tweet_data_list.nil?
    Time.now.to_s[/(\d*-)(\d*)(-\d*.*):\d* +\d*/]
    {tweets: tweets, latest_tweet_date: $1+format("%02d",$2.to_i-1)+$3}
  else
    latest_tweet_date = $tweet_data_list[0].time_and_day
    while(get_flag) do
      $tweet_data_list.each do |tweet|
        # 自分のtweetだけ抜き取る
        if tweet.account == session[:user][:name]
          if is_new_date(tweet.time_and_day, specify_date)
            # tweets_file.puts(tweet.tweet)
            tweets << tweet.tweet
          else
            get_flag = false
            break
          end
          p tweet.time_and_day
        end
      end

      # 使用済みtweet_dataの初期化
      $tweet_data_list = []

      if get_flag
        next_data = get_next_json(min_position)
        pull_out_tweet_data(next_data["html"])
        min_position = next_data["min_position"]
        p min_position
      end
    end

    # tweets_file.close
    {tweets: tweets, latest_tweet_date: latest_tweet_date}
  end
end

# get_tweets_up_to_specified_date("YYYY/MM/DD/ hh:mm")
# で取得が可能

# def main
#   get_tweets_up_to_specified_date("2019/08/01 00:00")
#   print_tweets
# end

# # 初期設定やらmainの呼び出し
# if __FILE__ == $0
#   # アカウント名が指定されていない or @で始まらないアカウント名なら終了
#   if ARGV.size() != 1 or ARGV[0] !~ /\A@.+\Z/
#     puts "Usage: Argv @[ACCOUNT_NAME]"
#     exit
#   end
#
#   # @を切り離したものをアカウント名として格納
#   session[:user][:name] = ARGV[0].delete("@")
#
#   # tweetのdataは1tweetごとにインスタンス化されて格納
#   $tweet_data_list = []
#
#   main
# end
#
