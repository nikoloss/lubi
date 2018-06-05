# coding: utf-8
require 'listen'
require 'fileutils'
require 'thread'
require 'set'
require './base/config'
require './base/facilities'


include FileUtils

#main
Lubi::Config.config
unless File.exists? Lubi::Config.dir
  #如果不存在同步盘目录则创建
  mkdir_p Lubi::Config.dir
end
unless File.exist? Lubi::Config.logDir
  #如果不存在日志目录则创建
  mkdir_p Lubi::Config.logDir
end
#切换到同步盘目录
cd Lubi::Config.dir

conn = Lubi::Facilities::Connection.new
conn.establish(ak:Lubi::Config.ak,sk:Lubi::Config.sk)
$mutex = Mutex.new
$op = false
$need_ignore = Set.new
logger = Logger.new(File::join(Lubi::Config.logDir, 'lubi.log'), 'weekly')
logger.level = Logger::INFO

def ignore_hidden_file(files, &p)
  files.each do |file|
    if hidden? file
      logger.info "captured #{file} but will ignore"
    else
      p.call(file)
    end
  end
end

def hidden?(file)
  file and File.basename(file).start_with? '.'
end

listener = Listen.to(".") do |m, a, r|
  $op = true
  #修改文件对应的操作是服务端删除文件再上传
  unless m.empty?
    $mutex.lock
    ignore_hidden_file m do |f|
      #绝对路径，需要去掉当前路径（同步盘路径）
      #比如f为 /home/rowland/qiniu/doc/ok.txt
      #则去掉同步盘路径之后得到 /doc/ok.txt
      #此时还需额外去掉开头那个"/"
      key = f.sub(pwd, "")[1..-1]
      if $need_ignore.include? key
        next
      end
      #删除服务器文件
      begin
        conn.netRm(key, Lubi::Config.bucket)
      rescue Lubi::Facilities::QiniuErr => qe
        logger.error qe
        sleep 1
        retry
      end

      #上传本地新文件
      etag = Lubi::Facilities::LubiFile.qetag(f)
      begin
        conn.upload(f, key, Lubi::Config.bucket)
      rescue Lubi::Facilities::QiniuErr => qe
        logger.error qe
        sleep 1
        retry
      end
      logger.info "#{key} modified!"
    end
    $mutex.unlock
  end
  #删除文件对应服务器删除
  #但是判断删除文件的时候需要同时
  #判断remove队列存在，add队列不存在
  if !r.empty? && a.empty?
    $mutex.lock
    ignore_hidden_file r do |f|
      key = f.sub(pwd, "")[1..-1]
      if $need_ignore.include? key
        next
      end
      begin
        conn.netRm(key, Lubi::Config.bucket)
        logger.info "#{key} deleted!"
      rescue Lubi::Facilities::QiniuErr => qe
        logger.error qe
        sleep 1
        retry
      end
    end
    $mutex.unlock
  end
  #新增文件的操作对应服务端直接上传
  #但是判断新增文件的时候需要判断remove是空
  if r.empty? && !a.empty?
    $mutex.lock
    ignore_hidden_file a do |f|
      key = f.sub(pwd, "")[1..-1]
      if $need_ignore.include? key
        next
      end
      etag = Lubi::Facilities::LubiFile.qetag(f)
      begin
        conn.upload(f, key, Lubi::Config.bucket)
      rescue Lubi::Facilities::QiniuErr => qe
        logger.error qe
        sleep 1
        retry
      end
      logger.info "#{key} added!"
    end
    $mutex.unlock
  end
  #重命名文件的操作，对应服务端改名
  #但是重命名操作的判断需要同时判断
  #add和remove队列不为空
  if !a.empty? && !r.empty?
    $mutex.lock
    r.zip(a) do |oldName, newName|
      oldKey = oldName.sub(pwd, "")[1..-1]
      newKey = newName.sub(pwd, "")[1..-1]
      if $need_ignore.include?(oldKey) || $need_ignore.include?(newKey)
        next
      end
      begin
        if hidden?(oldKey) && hidden?(newKey)
          logger.info "ignore renaming #{oldKey} to #{newKey}"
        elsif hidden?(oldKey) && !hidden?(newKey)
          #把一个隐藏文件改成普通文件，需要上传
          conn.upload(newName, newKey, Lubi::Config.bucket)
          logger.info "need add #{newKey}"
        elsif !hidden?(oldKey) && hidden?(newKey)
          #把一个普通文件改成隐藏文件，需要远程删除
          conn.netRm(oldKey, Lubi::Config.bucket)
          logger.info "need rm #{oldKey}"
        else
          conn.netRename(oldKey, newKey, Lubi::Config.bucket)
          logger.info "#{oldName} rename to #{newName}"
        end
      rescue Lubi::Facilities::QiniuErr => qe
        logger.error qe
        sleep 1
        retry
      end
    end
    $mutex.unlock
  end
  $op = false
end
listener.start
loop do
  begin
    $mutex.lock
    if $op
      $mutex.unlock
      sleep 1
      next
    end
    #由于我们已经cd到同步盘目录下了，所以直接列举当前目录"."就可以了
    local_files = Lubi::Facilities::LubiFile.list "."
    remote_files = conn.netList Lubi::Config.bucket
    $need_ignore = []
    need_down = []
    #实现步骤4
    remote_files.each_pair do |etag, f|
      if $op
        break
      end
      unless local_files[etag]
        if f["key"].index("/")
          #需要创建目录
          dirpath = f["key"][0..f["key"].rindex("/")]
          unless File.directory? dirpath
            mkdir_p dirpath
            logger.info "need create a directory=>#{dirpath}!"
          end
        end
        #下载之前让listener忽略该文件以免被捕获导致重新上传
        #添加到下载队列中
        need_down << f["key"]
        $need_ignore << f["key"]
      end
    end
    $mutex.unlock
    sleep 1
    #下载
    $mutex.lock
    if $op
      $mutex.unlock
      sleep 1
      next
    end
    need_down.each do |file|
      conn.download(file, file, Lubi::Config.bucket)
      logger.info "[loop]#{file} download."
    end
    $mutex.unlock
    sleep 1
    #实现步骤5
    #由于可能下载了新文件，所以需要重新获取远程文件列表以捕获刚刚下载的文件
    $mutex.lock
    remote_files = conn.netList Lubi::Config.bucket
    local_files = Lubi::Facilities::LubiFile.list "."
    need_remove = []
    need_rename = []
    local_files.each_pair do |etag, f|
      if f and hidden?f["key"]
        next
      end
      if not remote_files[etag]
        need_remove << f["key"]
        $need_ignore << f["key"]
      else
        unless f["key"] == remote_files[etag]["key"]
          #进入改名步骤
          if remote_files[etag]["key"].index("/")
            #需要创建目录
            dirpath = remote_files[etag]["key"][0..remote_files[etag]["key"].rindex("/")]
            unless File.directory? dirpath
              logger.info "need create a directory=>#{dirpath}!"
              mkdir_p dirpath
            end
          end
          #改名前让listener忽略该文件
          need_rename << [f["key"], remote_files[etag]["key"]]
          $need_ignore << f["key"]
          $need_ignore << remote_files[etag]["key"]
        end
      end
    end
    $mutex.unlock
    sleep 1
    $mutex.lock
    if $op
      $mutex.unlock
      sleep 1
      next
    end
    need_remove.each do |file|
      rm file
      logger.info "[loop] #{file} removed!"
    end
    need_rename.each do |oldFile, newFile|
      mv(oldFile, newFile)
      logger.info "[loop] #{oldFile} renamed to #{newFile}"
    end
    $mutex.unlock
    sleep 3 #轮询时间
  rescue Lubi::Facilities::QiniuErr => qe
    if $mutex.locked?
      $mutex.unlock
    end
    logger.error qe
    next
  end
end
