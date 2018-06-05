#coding=utf-8
require 'yaml'

module Lubi
  class Config
    #配置文件存放路径  /home/$user/.lubi.conf
    @@conf_dir = File::join(ENV["HOME"], ".lubi.conf")
    #dir为本地同步盘目录
    @ak, @sk, @bucket = nil, nil, nil
    @dir = File::join(ENV["HOME"], "lubi")
    @logDir = File.absolute_path(File::join('.', "lubi_log"))
    class << self
      attr_reader :ak, :sk, :bucket, :dir, :logDir
      def shape
        conf = {}
        loop do
          STDOUT << "ak? "
          conf[:ak] = STDIN.readline.strip
          break if !conf[:ak].nil? && !conf[:ak].empty?
        end
        loop do
          STDOUT << "sk? "
          conf[:sk] = STDIN.readline.strip
          break if !conf[:sk].nil? && !conf[:sk].empty?
        end
        loop do
          STDOUT << "bucket? "
          conf[:bucket] = STDIN.readline.strip
          break if !conf[:bucket].nil? && !conf[:bucket].empty?
        end
        STDOUT << "which directory? default [#{@dir}] "
        syncDir = STDIN.readline.strip
        conf[:dir] = @dir
        conf[:dir] = syncDir if !syncDir.nil? && !syncDir.empty?
        STDOUT << "log directory? default [#{@logDir}] "
        logDir = STDIN.readline.strip
        conf[:log_dir] = @logDir
        conf[:log_dir] = logDir if !logDir.nil? && !logDir.empty?
        File.open(@@conf_dir, "w") do |f|
          YAML.dump(conf, f)
        end
      end

      def config
        shape until File.exist? @@conf_dir
        conf = YAML.load_file(@@conf_dir)
        @ak, @sk, @bucket, @dir, @logDir = conf[:ak], conf[:sk], conf[:bucket], conf[:dir], conf[:log_dir]
      end
    end
  end
end
