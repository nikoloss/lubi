#coding=utf-8
require 'yaml'

module Lubi
    class Config
        @@conf_dir = File::join(ENV["HOME"], ".lubi.conf")
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
