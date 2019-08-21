class TweetData

  def initialize(html)
    # アカウント名を取得
    @account = html[/data-screen-name="(.+?)"/, 1]

    # tweet日時を取得 [yyyy, mm, dd]
    @time_and_day = html[%r{<small class="time">(.+?)</small>}m][/title="(.+?)"/, 1]
    if @time_and_day =~ /(\d*):(\d*) - (\d*).+?(\d*).+?(\d*).+/
      @time_and_day = "#{fm(4, $3)}/#{fm(2, $4)}/#{fm(2, $5)} #{fm(2, $1)}:#{fm(2, $2)}"
    end

    # tweet内容のみを抽出
    @tweet = html[%r{<div class="js-tweet-text-container">(.+?)</div>}m][%r{<p.+?>(.+?)</p>}m, 1]
    # 画像があればリンクを削除
    @tweet = $1 if @tweet =~ %r{(.*?)<a.+</a>}
    # 絵文字なども削除
    while @tweet =~ /<img .+? title="(.+?)" .+?>/
      img = "[" + $1 + "]"
      @tweet = @tweet.sub(/<img.+?>/, img)
    end
  end

  def account
    @account
  end

  def time_and_day
    @time_and_day
  end

  def tweet
    @tweet
  end

  private
  def fm(digit, num)
    format("%0#{digit}d", num.to_i)
  end
end
