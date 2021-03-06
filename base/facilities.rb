#coding=utf-8
require 'qiniu'
require 'digest'
require 'base64'
require 'find'
require 'open-uri'

BLOCK_SIZE = 2 ** 22

module Lubi
  module Facilities
    class MissArgErr < Exception
      def initialize key
        super("require arg \"#{key}\" was not found!")
      end
    end

    class QiniuErr < Exception
    end

    class LubiFile
      class << self
        def qetag(file_name)
          sha1 = []
          open(file_name, "rb") do |f|
            until f.eof?
              chunk = f.read(BLOCK_SIZE)
              sha1 << Digest::SHA1.digest(chunk)
            end
          end
          if sha1.size == 1
            Base64.urlsafe_encode64(0x16.chr + sha1[0])
          else
            Base64.urlsafe_encode64(0x96.chr + Digest::SHA1.digest(sha1.join))
          end
        end

        def list(dir)
          localHash = {}
          Find.find(dir) do |f|
            if f && File.file?(f)
              localFile = {}
              localFile["name"] = f
              if f.start_with? "./"
                localFile["key"] = f[2..-1]
              else
                localFile["key"] = f
              end
              localFile["hash"] = Lubi::Facilities::LubiFile.qetag(File.absolute_path(f))
              localHash[localFile["hash"]] = localFile
            end
          end
          localHash
        end
      end
    end

    class Connection

      def establish opt={}
        #check params
        [:ak, :sk].each do |key|
          raise MissArgErr, key unless opt.has_key? key
        end
        #real qiniu establish
        Qiniu.establish_connection! access_key: opt[:ak], secret_key: opt[:sk]
      end

      def upload(localFilePath, keyName, bucketName)
        put_policy = Qiniu::Auth::PutPolicy.new(bucketName, keyName)
        uptoken = Qiniu::Auth.generate_uptoken put_policy
        code, result, response_headers = Qiniu::Storage.upload_with_token_2(
          uptoken,
          localFilePath,
          keyName,
          nil,
          bucket: bucketName)
        raise QiniuErr, "qiniu:upload[#{localFilePath}] error!" if code != 200
      end

      def download(localFilePath, keyName, bucketName)
        code, resp = Qiniu::Storage.domains(bucketName)
        raise QiniuErr, "qiniu:download #{keyName} [#{code}]" unless code==200
        domain = resp[0]["domain"]
        primitive_url = "http://" << domain << "/"<< URI.encode(keyName).gsub("[","%5B").gsub("]","%5D")
        download_url = Qiniu::Auth.authorize_download_url(primitive_url)
        begin
          IO.copy_stream(open(download_url), localFilePath)
        rescue
          raise QiniuErr, "qiniu:download #{keyName} error, uri=[#{download_url}], keyName=[#{keyName}]"
        end
      end

      def netRm(keyName, bucketName)
        code = 0
        3.times do
          code, result, resp = Qiniu::Storage.delete(bucketName, keyName)
          break if [200].include? code
        end
        raise QiniuErr, "qiniu:remove [#{keyName}] error!" unless 200 == code
      end

      def netRename(oldKeyName, newKeyName, bucketName)
        code, result, resp = Qiniu::Storage.move(bucketName, oldKeyName, bucketName, newKeyName)
        raise QiniuErr, "qiniu:[#{oldKeyName}] rename [#{newKeyName}] error!" unless [200, 612, 614].include? code
      end

      def netList(bucketName)
        items = []
        code, resp, headers, has_more, list_policy = nil, nil, nil, true, Qiniu::Storage::ListPolicy.new(bucketName)
        while has_more do
          code, resp, headers, has_more, list_policy = Qiniu::Storage.list(list_policy)
          raise QiniuErr, "qiniu list error!" unless (code == 200 && resp.is_a?(Hash))
          items += resp["items"] if resp.has_key? "items"
        end
        itemsHash = {}
        items.each do |item|
          itemsHash[item["hash"]] = item
        end
        itemsHash
      end
    end

  end
end
