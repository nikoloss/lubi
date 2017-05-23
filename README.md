# lubi 七牛同步盘
#### 先申请七牛开发者账号，配置云存储空间。

```
$> cd $yourWorkSpace
$> git clone https://github.com/nikoloss/lubi.git
$> cd lubi
$> bundle install #install dependency
$> bundle exec ruby lubi.rb
```
首次执行会提示设置七牛ak, sk, bucketName以及同步盘路径（绝对路径）
