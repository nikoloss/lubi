#coding=utf-8
require 'yaml'

module Lubi
  class Config
    #配置文件存放路径  /home/$user/.lubi.conf
    @@conf_dir = File::join(ENV["HOME"], ".lubi.conf")
    #dir为本地同步盘目录
    @ak, @sk, @bucket, @dir = nil, nil, nil, nil
    class << self
      attr_reader :ak, :sk, :bucket, :dir
      def shape
        conf = {}
        $stdout << "ak? "
        conf[:ak] = $stdin.readline.strip
        $stdout << "sk? "
        conf[:sk] = $stdin.readline.strip
        $stdout << "bucket? "
        conf[:bucket] = $stdin.readline.strip
        $stdout << "which directory? "
        conf[:dir] = $stdin.readline.strip
        File.open(@@conf_dir, "w") do |f|
          YAML.dump(conf, f)
        end
      end

      def config
        shape until File.exist? @@conf_dir
        conf = YAML.load_file(@@conf_dir)
        @ak, @sk, @bucket, @dir = conf[:ak], conf[:sk], conf[:bucket], conf[:dir]
      end
    end
  end
end
