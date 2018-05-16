/* A Little Web Server
 * valac --pkg gio-2.0 ltweb.vala -o ltweb
 * valac --pkg gio-2.0 ltweb.vala -C
 * gcc `pkg-config --cflags glib-2.0` -c ltweb.c
 * gcc ltweb.o -o ltweb `pkg-config --libs glib-2.0,gobject-2.0,,gio-2.0`
 * this project can run be with openwrt/lede
 */

using GLib;
//what port are we serving on?
const uint16 PORT = 8082;

namespace StatusCode {
  const string FILE_NOT_FOUND = "HTTP/1.1 404 Not Found\n"; 
  const string OK = "HTTP/1.1 200 OK\n"; 
  const string ERROR = "HTTP/1.1 500 Internal Server Error\n"; 
}

struct Request {
  string full_request;
  string path;
  string query;
  HashTable<string, string> args;
  string object;
  string action;
  string val;
}

struct Response {
  string status_code;
  string content_type;
  string text;
  uint8[] data;
}

public class WebServer {
  
  private ThreadedSocketService tss;
  private string public_dir;
  private Regex ext_reg;
  
  public WebServer() {
    public_dir="public";
    try {
      ext_reg = new Regex("\\.(?<ext>[a-z]{2,4})$");
    } catch(Error e) {
      stderr.printf(e.message+"\n");
    }
    //make the threaded socket service with hella possible threads
    tss = new ThreadedSocketService(150);
    //create an IPV4 InetAddress bound to no specific IP address
    InetAddress ia = new InetAddress.any(SocketFamily.IPV4);
    //create a socket address based on the netadress and set the port
    InetSocketAddress isa = new InetSocketAddress(ia, PORT);
    //try to add the address to the ThreadedSocketService
    try {
      tss.add_address(isa, SocketType.STREAM, SocketProtocol.TCP, null, null);
    } catch(Error e) {
      stderr.printf(e.message+"\n");
      return;
    }
    /* connect the 'run' signal that is emitted when 
     * there is a connection to our connection handler
     */
    tss.run.connect( connection_handler );
  }
  
  public void run() {
    //we need a gobject main loop
    MainLoop ml = new MainLoop();
    //start listening 
    tss.start();
    stdout.printf(@"Serving on port $PORT\n");
    //run the main loop
    ml.run();
  }
  //when a request is made, handle the socket connection
  private bool connection_handler(SocketConnection connection) {
    string first_line ="";
    size_t size = 0;
    Request request = Request();
    //get data input and output streams for the connection
    DataInputStream dis = new DataInputStream(connection.input_stream);
    DataOutputStream dos = new DataOutputStream(connection.output_stream);  
    //read the first line from the input stream
    try {
      first_line = dis.read_line( out size );
      request = get_request( first_line );
      
    } catch (Error e) {
      stderr.printf(e.message+"\n");
    }
    //build a response based on the request
    Response response = Response();
    response = get_file_response(request);
    serve_response( response, dos );
    return false;
  }
  
  private void serve_response(Response response, DataOutputStream dos) {
    try {
      var data = response.data ?? response.text.data;
      dos.put_string(response.status_code);
      dos.put_string("Server: ltwebSocket\n");
      dos.put_string("Content-Type: %s\n".printf(response.content_type));
      dos.put_string("Content-Length: %d\n".printf(data.length));
      dos.put_string("\n");//this is the end of the return headers
      /* For long string writes, a loop should be used,
       * because sometimes not all data can be written in one run 
       *  see http://live.gnome.org/Vala/GIOSamples#Writing_Data
       */ 
      long written = 0;
      while (written < data.length) { 
          // sum of the bytes of 'text' that already have been written to the stream
          written += dos.write (data[written:data.length]);
      }
    } catch( Error e ) {
      stderr.printf(e.message+"\n");
    }
  }
  
  private Response get_file_response(Request request) {
    //default request.path = index.htm
    string request_path = (request.path=="/") ? "index.htm" : request.full_request;
    stdout.printf ("%s\n", request_path);
    string filepath= Path.build_filename(public_dir, request_path);
//string filepath= "index.htm";
    stdout.printf ("%s\n", filepath);
    Response response = Response();
    response.content_type = "text/plain";
    response.status_code = StatusCode.ERROR;
    //does the file exist?
    if (FileUtils.test(filepath, GLib.FileTest.IS_REGULAR) ) {
      //serve the file
      bool read_failed = true;
      uint8[] data = {};
       try {
        FileUtils.get_data(filepath, out data);
        response.data = data;
        response.content_type = get_content_type( filepath );
        response.status_code = StatusCode.OK;
        read_failed = false;
      } catch (Error err) {
        response.text = err.message;
        response.status_code = StatusCode.ERROR;
        response.content_type="text/plain";
      }    
    } else {
      //file not found
      response.status_code = StatusCode.FILE_NOT_FOUND;
      response.content_type = "text/plain";
      response.text = "File Not Found";
    }
    return response;
  }
  
  private string get_content_type(string file) {
    //get the extension
    MatchInfo mi;
    ext_reg.match( file, 0, out mi );
    var ext = mi.fetch_named("ext");
    string content_type = "text/plain";
    if (ext!=null) {
      string lower_ext = ext.down();
      switch(lower_ext) {
        case "htm":
        case "html":
          content_type="text/html";
          break;
        case "xml":
          content_type="text/xml";
          break;
        case "js":
        case "json":
          content_type="text/javascript";
          break;
        case "css":
          content_type="text/css";
          break;
        case "ico":
          content_type="image/icon";
          break;
        case "png":
          content_type="image/png";
          break;
        case "jpg":
          content_type="image/jpeg";
          break;
        case "gif":
          content_type="image/gif";
          break;
      }
    }
    return content_type;
  }
  
  // return a Request based on a portion of th line
  private Request get_request(string line) {
    Request r = Request();
    r.args = new HashTable<string, string>(str_hash, str_equal);
    //get the parts from the line
    string[] parts = line.split(" ");
 stdout.printf ("%s\n",  line);
    //how many parts are there?
    if (parts.length == 1) {
      return r;
    }
    //add the path to the Request
    r.full_request = parts[1];
    parts = r.full_request.split("?");
    r.path = parts[0];
    r.query = parts[1] ?? "";
    //get the object and action
    parts = r.path.split("/");
    if (parts.length > 1) {
      r.object = parts[1] ?? "";
    }
    if (parts.length > 2) {
      r.action = parts[2] ?? "";
    }
    if (parts.length > 3) {
      r.val = Uri.unescape_string(parts[3]) ?? "";
    }
    //split the query if it exists
    if (r.query != "") {
      string[] query_parts={};
      parts = r.query.split("&");
      foreach( string part in parts ) {
        query_parts = part.split("=");
        if (query_parts.length == 2){
          r.args[query_parts[0]] = Uri.unescape_string(query_parts[1]);
        }
      }
    }
    return r;
  } 
}

public static void main() {
  WebServer ws = new WebServer();
  ws.run();
}
