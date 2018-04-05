## SeasLog 日志收集

日志处理过程一般是 `输出日志 -> 收集日志 -> 分析日志 -> 存储日志 -> 后台管理`

本文将使用:
```
输出日志: SeasLog

收集日志: Rsyslog, Filebeat, Logstash

分析日志: Rsyslog, Logstash

存储日志: Elasticsearch
```
可自由搭配结合

### SeasLog 输出日志到 Rsyslog

本文统一 SeasLog 模板为 `seaslog.default_template = "%T | %M"`

#### 1. 使用 File

1. 修改 SeasLog 配置为 File 输出

```conf
;日志存储介质 1File 2TCP 3UDP (默认为1)
seaslog.appender = 1

;默认log根目录
seaslog.default_basepath = "/www/wwwlogs/seaslog"

;默认logger目录
seaslog.default_logger = "default"
```

2. 修改 Rsyslog 配置开启 [imfile](http://www.rsyslog.com/doc/v8-stable/configuration/modules/imfile.html) 输入模块

```conf
#载入 imfile 模块
module(load="imfile" PollingInterval="10")

#使用 imfile 模块监听 `/www/wwwlogs/seaslog/default/` 文件夹下 .log 文件
input(type="imfile"
    File="/www/wwwlogs/seaslog/default/*.log"
    Tag="tag1"
    Severity="error"
    Facility="local7")
```

#### 2. 使用 TCP/UDP

SeasLog 中使用 [RFC5424](https://tools.ietf.org/html/rfc5424) 规范远程输出日志

输出日志格式为 `<{PRI}>1 {time_RFC3339} {host_name} {domain_port} {process_id} {logger} {log_message}`

具体使用 TCP 还是 UDP 根据业务需求来定, 下面使用 TCP 为例

1. 服务端: 修改 Rsyslog 配置开启 [imtcp](http://www.rsyslog.com/doc/v8-stable/configuration/modules/imtcp.html) 输入模块

```conf
#载入 imtcp 模块
module(load="imtcp")

#使用 imtcp 模块监听 514 端口作为输入
input(type="imtcp" port="514")
```

2. 客户端: 修改 SeasLog 配置使用 TCP

```conf
;日志存储介质 1File 2TCP 3UDP (默认为1)
seaslog.appender = 2

;接收ip 默认127.0.0.1 (当使用TCP或UDP时必填)
seaslog.remote_host = "192.168.0.1"

;接收端口 默认514 (当使用TCP或UDP时必填)
seaslog.remote_port = 514
```

### Rsyslog 处理日志

#### 1. 在未定义 template 的时候, Rsyslog 会使用默认模板对日志进行格式化

例如 rsyslogd 7.6.1 

默认模板是: [`RSYSLOG_TraditionalFileFormat`](https://www.rsyslog.com/doc/v8-stable/configuration/templates.html)

定义: `$template TraditionalFileFormat,"%TIMESTAMP% %HOSTNAME% %syslogtag%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n" `

%rawmsg% 是

`<14>1 2018-04-04T18:02:04+08:00 whj-desktop cli 30479 default 2018-04-04 18:02:04 | i am cli test seaslog rsyslog`

%msg% 是

`Apr  4 18:08:10 whj-desktop cli[4518] 2018-04-04 18:08:10 | i am cli test seaslog rsyslog`

更多 Rsyslog [properties](http://www.rsyslog.com/doc/v8-stable/configuration/properties.html)

#### 2. Rsyslog 输出到文件

配置 [template](http://www.rsyslog.com/doc/v8-stable/configuration/templates.html)

```conf
#定义一个模板将日志打入 seaslog_%$year%%$month%%$day%.log
$template logfile,    "/var/log/seaslog_%$year%%$month%%$day%.log"

#定义一个模板对日志内容进行格式化
template(name="logformat" type="string" string="app-name: %APP-NAME%\nmsgid: %MSGID% \nmsg: %msg% \nrawmsg: %rawmsg% \n\n")

#使用contains 搜索含有 `seaslog` 关键字的日志并使用上面定义的那两个模板
:msg,contains,        "seaslog"            ?logfile;logformat
```

TCP/UDP 输出, Rsyslog 的 rawmsg 原始日志格式为[RFC5424](https://tools.ietf.org/html/rfc5424) 规范 `<{PRI}>1 {time_RFC3339} {host_name} {domain_port} {process_id} {logger} {log_message}`

```
app-name: cli
msgid: default 
msg: 2018-04-04 18:02:09 | i am cli test seaslog rsyslog 
rawmsg: <14>1 2018-04-04T18:02:09+08:00 whj-desktop cli 30551 default 2018-04-04 18:02:09 | i am cli test seaslog rsyslog
```

File 输出, Rsyslog 采集到的日志格式是 `seaslog.default_template`

```
app-name: tag1
msgid: - 
msg: 2018-04-04 18:05:44 | i am cli test seaslog rsyslog 
rawmsg: 2018-04-04 18:05:44 | i am cli test seaslog rsyslog 
```


#### 3. Rsyslog 输出到 Logstash 和 elasticsearch

配置 Logstash 的 input 为 syslog, 端口 5555

```conf
input {
    syslog {
        type => "rsyslog"
        port => "5555"
    }
}
```
配置 Logstash 的 output 到 elasticsearch

```conf
output{
    if [type] == "rsyslog" {
        elasticsearch {
            hosts => ["127.0.0.1:9200"] 
            index => "rsyslog-%{+YYYY.MM.dd}"
        }
    }
}
```
将 Rsyslog 日志重定向到 Logstash

```conf
:msg,contains 'seaslog' @@172.17.0.2:5555
```

### 使用 Filebeat 收集日志
收集 `/var/log/seaslog_*.log` 的日志并输出到 logstash

```yml
- type: log
  enabled: true
  paths:
    - /var/log/seaslog_*.log
output.logstash:
  hosts: ["localhost:5044"]
  ssl.certificate_authorities: ["/home/whj/logstash-beats.crt"]
```
配置 logstash 的 input 为 beats
```conf
input {
  beats {
    port => 5044
    ssl => true
    ssl_certificate => "/etc/pki/tls/certs/logstash-beats.crt"
    ssl_key => "/etc/pki/tls/private/logstash-beats.key"
  }
}
```
### 直接 SeasLog TCP 输出到 logstash

客户端: 修改 SeasLog 配置使用 TCP

```conf
;日志存储介质 1File 2TCP 3UDP (默认为1)
seaslog.appender = 2

;接收ip 默认127.0.0.1 (当使用TCP或UDP时必填)
seaslog.remote_host = "127.0.0.1"

;接收端口 默认514 (当使用TCP或UDP时必填)
seaslog.remote_port = 5555
```
