require 'listen'
require 'fileutils'
require './base/config'
require './base/facilities'

include FileUtils

#main
Lubi::Config.config
unless File.exists? Lubi::Config.dir
    #如果不存在同步盘目录则创建
    mkdir_p Lubi::Config.dir
end
#切换到同步盘目录
cd Lubi::Config.dir

conn = Lubi::Facilities::Connection.new
conn.establish(ak:Lubi::Config.ak,sk:Lubi::Config.sk)

loop {
    #由于我们已经cd到同步盘目录下了，所以直接列举当前目录"."就可以了
    local_files = Lubi::Facilities::LubiFile.list "."
    remote_files = conn.netList Lubi::Config.bucket
    puts "local_files=>#{local_files}"
    puts "remote_files=>#{remote_files}"
    #实现步骤4
    remote_files.each_pair do |etag, f|
        unless local_files[etag]
            if f["key"].index("/")
                #需要创建目录
                filepath = f["key"][0..f["key"].rindex("/")]
                puts "need create a directory=>#{filepath}!"
                unless File.directory? filepath
                    mkdir_p filepath
                end
            end
            #downloading!
            conn.download(f["key"], f["key"], Lubi::Config.bucket)
            puts "#{f["key"]} downloaded!!!"
        end
    end
    #实现步骤5
    local_files.each_pair do |etag, f|
        unless remote_files[etag]
            unless f["using"]
                puts "#{f["key"]} needs to be deleted!"
                rm f["key"]
            end
        else
            unless f["key"] == remote_files[etag]["key"]
                #进入改名步骤
                puts "#{f["key"]} rename to #{remote_files[etag]["key"]}"
                if remote_files[etag]["key"].index("/")
                    #需要创建目录
                    filepath = remote_files[etag]["key"][0..remote_files[etag]["key"].rindex("/")]
                    puts "need create a directory=>#{filepath}!"
                    unless File.directory? filepath
                        mkdir_p filepath
                    end
                end
                mv(f["key"], remote_files[etag]["key"])
            end
        end
    end
    sleep 30 #轮询时间 30秒
}
