import std/uri
echo "1: ", parseUri("http://[::1]:8080/api").hostname
echo "2: ", parseUri("http://[::1").hostname
echo "3: ", parseUri("http://::1:8080/api").hostname
