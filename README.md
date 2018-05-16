1 server 编译
valac --pkg gio-2.0 ltweb.vala -o ltweb

2 clinet 编译
gcc http.c -o http

3 在server目录下建立public目录并放上测试文件data.txt

4 测试 ./http data.txt

Request:
GET /data.txt HTTP/1.1


Response:
HTTP/1.1 200 OK
Server: ltwebSocket
Content-Type: text/plain
Content-Length: 38

3412542314123412341234534255456765467

5 此项目的所有代码均可运行于openwrt/lede
