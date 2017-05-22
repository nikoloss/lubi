require 'listen'
require 'fileutils'
require './base/config'
require './base/facilities'

include FileUtils

#main
Lubi::Config.config
cd Lubi::Config.dir

conn = Lubi::Facilities::Connection.new
conn.establish(ak:Lubi::Config.ak,sk:Lubi::Config.sk)

loop {
    local_files = Lubi::Facilities::LubiFile.list "."
    remote_files = conn.netList Lubi::Config.bucket
    puts "local_files=>#{local_files}"
    puts "remote_files=>#{remote_files}"
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

    sleep 30
}
