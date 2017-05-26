# coding: utf-8
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

$using_files = {}

def inusing(files, &p)
  begin
    lock_inuse files
    p.call
  ensure
    unlock_inuse files
  end
end

def lock_inuse(files)
  #文件打标！防止对同一文件进行多种操作
  files.each do |file|
    etag = Lubi::Facilities::LubiFile.qetag file
    $using_files[etag] = "using"
  end
end

def unlock_inuse(files)
  #去掉标记！
  files.each do |file|
    etag = Lubi::Facilities::LubiFile.qetag file
    $using_files.delete(etag) if $using_files[etag]
  end
end

listener = Listen.to(".") do |m, a, r|
  #修改文件对应的操作是服务端删除文件再上传
  unless m.empty?
    inusing m do 
      m.each do |f|
        #绝对路径，需要去掉当前路径（同步盘路径）
        #比如f为 /home/rowland/qiniu/doc/ok.txt
        #则去掉同步盘路径之后得到 /doc/ok.txt
        #此时还需额外去掉开头那个"/"
        key = f.sub(pwd, "")[1..-1]
        #删除服务器文件
        begin
          conn.netRm(key, Lubi::Config.bucket)
        rescue Lubi::Facilities::QiniuErr => qe
          puts qe
          sleep 5
          retry
        end

        #上传本地新文件
        etag = Lubi::Facilities::LubiFile.qetag(f)
        begin
          conn.upload(f, key, Lubi::Config.bucket)
        rescue Lubi::Facilities::QiniuErr => qe
          puts qe
          sleep 5
          retry
        end
        puts "#{key} modified!"
      end
    end
  end
  #删除文件对应服务器删除
  #但是判断删除文件的时候需要同时
  #判断remove队列存在，add队列不存在
  if !r.empty? && a.empty?
    r.each do |f|
      key = f.sub(pwd, "")[1..-1]
      begin
        conn.netRm(key, Lubi::Config.bucket)
        puts "#{key} deleted!"
      rescue Lubi::Facilities::QiniuErr => qe
        puts qe
        sleep 5
        retry
      end
    end
  end
  #新增文件的操作对应服务端直接上传
  #但是判断新增文件的时候需要判断remove是空
  if r.empty? && !a.empty?
    inusing a do
      a.each do |f|
        key = f.sub(pwd, "")[1..-1]
        etag = Lubi::Facilities::LubiFile.qetag(f)
        begin
          conn.upload(f, key, Lubi::Config.bucket)
        rescue Lubi::Facilities::QiniuErr => qe
          puts qe
          sleep 5
          retry
        end
        puts "#{key} added!"
      end
    end
  end
  #重命名文件的操作，对应服务端改名
  #但是重命名操作的判断需要同时判断
  #add和remove队列不为空
  if !a.empty? && !r.empty?
    inusing a do
      r.zip(a) do |oldName, newName|
        oldKey = oldName.sub(pwd, "")[1..-1]
        newKey = newName.sub(pwd, "")[1..-1]
        begin
          conn.netRename(oldKey, newKey, Lubi::Config.bucket)
        rescue Lubi::Facilities::QiniuErr => qe
          puts qe
          sleep 5
          retry
        end
        puts "#{oldName} rename to #{newName}"
      end
    end
  end
end
listener.start
loop {
  begin
    sleep 10 #轮询时间
    #由于我们已经cd到同步盘目录下了，所以直接列举当前目录"."就可以了
    local_files = Lubi::Facilities::LubiFile.list "."
    remote_files = conn.netList Lubi::Config.bucket
    #puts "local_files=>#{local_files}"
    #puts "remote_files=>#{remote_files}"
    #实现步骤4
    remote_files.each_pair do |etag, f|
      unless local_files[etag]
        if f["key"].index("/")
          #需要创建目录
          dirpath = f["key"][0..f["key"].rindex("/")]
          unless File.directory? dirpath
              mkdir_p dirpath
              puts "need create a directory=>#{dirpath}!"
          end
        end
        #下载之前让listener忽略该文件以免被捕获导致重新上传
        listener.ignore! Regexp.new(Regexp.escape(f["key"]))
        conn.download(f["key"], f["key"], Lubi::Config.bucket)
        sleep 1
        listener.ignore! nil
        puts "#{f["key"]} downloaded!!!"
      end
    end
    #实现步骤5
    #由于步骤4下载了新文件，所以local_files需要更新一次以捕获刚刚下载的文件
    local_files = Lubi::Facilities::LubiFile.list "."
    local_files.each_pair do |etag, f|
      unless $using_files[etag]
        unless remote_files[etag]
          listener.ignore! Regexp.new(Regexp.escape(f["key"]))
          rm f["key"]
          puts "#{f["key"]} deleted!"
          sleep 1
          listener.ignore! nil
        else
          unless f["key"] == remote_files[etag]["key"]
            #进入改名步骤
            if remote_files[etag]["key"].index("/")
              #需要创建目录
              dirpath = remote_files[etag]["key"][0..remote_files[etag]["key"].rindex("/")]
              unless File.directory? dirpath
                puts "need create a directory=>#{dirpath}!"
                mkdir_p dirpath
              end
            end
            #改名前让listener忽略该文件
            listener.ignore! [Regexp.new(Regexp.escape(f["key"])),
                              Regexp.new(Regexp.escape(remote_files[etag]["key"]))]
            mv(f["key"], remote_files[etag]["key"])
            sleep 1
            listener.ignore! nil
            puts "#{f["key"]} rename to #{remote_files[etag]["key"]}"
          end
        end
      end
    end
  rescue Lubi::Facilities::QiniuErr => qe
    puts qe
    next
  end
}
