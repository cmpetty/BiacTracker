/**
 * Head tracker sketch to be used with arduino uno and 9 DOF IMU
 * https://www.sparkfun.com/products/10724
 * arduino is loaded with FreeIMU's 9 DOF firmware https://github.com/ptrbrtz/razor-9dof-ahrs/wiki/Tutorial
 * 09/2014 - Chris Petty
 */
import java.util.Properties;

import org.apache.http.impl.client.DefaultHttpClient;
import org.apache.http.client.HttpClient;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.HttpResponse;
import org.apache.http.HttpEntity;
import org.apache.http.util.EntityUtils;
import org.json.*;

import processing.serial.*;
import controlP5.*;
PGraphics pg;

//cp5 objects
ControlP5 cp5;
Toggle toggle, toggle2, toggle3;
Slider slider;
Textarea alertBox, dirBox;

//a font
PFont f;

//serial connection
Serial serial;
boolean synched = false;

//values from sensor
float yaw = 0.0f;
float pitch = 0.0f;
float roll = 0.0f;
public float yawOffset = 0.0f; 
public float pitchOffset = 0.0f;
public float rollOffset = 0.0f;

//values for gui
color bgColor = #000000;
color boxColor = bgColor;
color warnColor = #C0392B;
public float slideVal = 8.0;
public boolean doAlert = false;
public boolean doLevel = false;
public boolean doPause = false;
public boolean isPaused = false;
public int pauseTime = millis();
final static int pauseDur = 3000;

//defauts for serial connections
//final static int SERIAL_PORT_NUM = 0; //5 on my mac, 0 on windows

public int SERIAL_PORT_NUM; //will detect with regex
final static int SERIAL_PORT_BAUD_RATE = 57600;
public String portName; //will be used to select serial port

//vals for plot
int xPos = 1;
float lastY = 0.0, lastP = 0.0, lastR = 0.0;
FloatList norm_vals = new FloatList();

//size of main screen
public static int screenWidth=1024;

//http stuff for interacting with VLC
HttpClient client = new DefaultHttpClient();
//String url = "http://:dummypass@localhost:8080/requests/status.json?command=pl_pause";
String defaultpass = "dummypass";
String defaultport = "8080";
String baseurl;
HttpResponse response = null;
HttpEntity entity = null;


// Skip incoming serial stream data until token is found
boolean readToken(Serial serial, String token) {
  // Wait until enough bytes are available
  if (serial.available() < token.length())
    return false;
  
  // Check if incoming bytes match token
  for (int i = 0; i < token.length(); i++) {
    if (serial.read() != token.charAt(i))
      return false;
  }
  
  return true;
}

void setup() {
  //load any command line args
  Properties props = loadCommandLine();
  
  f = createFont("Arial",16,true); // Arial, 16 point, anti-aliasing on
   
  size(screenWidth, 768);
  smooth();  
  frame.setTitle("BIAC Tracker");
  
  //create an offscreen graphics buffer just for plot
  pg = createGraphics(width-10,height-150);
  
  cp5 = new ControlP5(this);

  //grouping of cp5 objects for GUI
  Group g1 = cp5.addGroup("g1")
    .setPosition(5, height - 85)
    .setWidth(width - 10)
    .setBackgroundHeight(80)
    .setBackgroundColor(color(255,50))
    .setLabel("CONTROLS")
    ;

  //slider for alerts
  slider = cp5.addSlider("slideVal")
  .setPosition(10, g1.getHeight() / 2 + 10)
  .setSize(200, 40)
  .setScrollSensitivity(0.01)
  .setRange(0,90)
  .setValue(slideVal)
  .setNumberOfTickMarks(22)
  .setGroup(g1)
  ;

  slider.captionLabel().set("degrees");

  //turn on/off alerting functionality
   toggle = cp5.addToggle("alert")
    .setPosition(slider.getPosition().x + slider.getWidth() + 70, slider.getPosition().y )
    .setColorForeground(color(120))
    .setColorActive(color(255))
    .setColorLabel(color(255))
    .setSize(40, 40)
    .setGroup(g1)
    ;
 
 //move the toggle label to be beside
  Label l=toggle.captionLabel(); 
  l.style().marginTop = toggle.getHeight()/-2 - 8;
  l.style().marginLeft = toggle.getWidth() + 5;
 
   //turn on/off leveling functionality
   toggle2 = cp5.addToggle("level")
    .setPosition(toggle.getPosition().x + toggle.getWidth() + 50, toggle.getPosition().y )
    .setColorForeground(color(120))
    .setColorActive(color(255))
    .setColorLabel(color(255))
    .setSize(40, 40)
    .setGroup(g1)
    ;

 //move the kevek label to be beside
  Label l2=toggle2.captionLabel(); 
  l2.style().marginTop = toggle2.getHeight()/-2 - 8;
  l2.style().marginLeft = toggle2.getWidth() + 5;


   //turn on/off leveling functionality
   toggle3 = cp5.addToggle("pause")
    .setPosition(toggle2.getPosition().x + toggle2.getWidth() + 50, toggle2.getPosition().y )
    .setColorForeground(color(120))
    .setColorActive(color(255))
    .setColorLabel(color(255))
    .setSize(40, 40)
    .setGroup(g1)
    ;

  toggle3.captionLabel().set("pause vlc");

 //move the kevek label to be beside
  Label l3=toggle3.captionLabel(); 
  l3.style().marginTop = toggle3.getHeight()/-2 - 8;
  l3.style().marginLeft = toggle3.getWidth() + 5;



  //textbox to act as visual alert for threshold
  alertBox = cp5.addTextarea("alertBox")
    .setPosition(g1.getWidth() - 70,g1.getHeight() / 2 + 10)
    .setSize(55,55)
    .setColor(color(255))
    .setColorBackground(boxColor)
    .setColorForeground(color(255))
    .setGroup(g1)
  ;
 
 
 
 //add some instructions
 dirBox = cp5.addTextarea("dirBox")
   .setPosition(toggle3.getPosition().x + toggle3.getWidth() + 75, toggle3.getPosition().y )
   .setSize(300,55)
   .setColor(color(255))
   .setColorBackground(bgColor)
   .setColorForeground(color(255))
   .setFont(createFont("arial",12))
   .setLineHeight(10)
   .setGroup(g1)
  ;

  dirBox.setText("a = normalize YPR values by current position\n"
      + "p = pause the current playing VLC movie");
      
  cp5.getTooltip().setDelay(500);
  cp5.getTooltip().register("slideVal","set a threshold for alerts of YPR values in degrees.");
  cp5.getTooltip().register("alert","turn on/off visual alerts.");
  cp5.getTooltip().register("level","turn on/off automatic leveling of YPR lines.");
  cp5.getTooltip().register("pause","pause the VLC player of YPR go above set threshold.");


  //add another group for the 3D cube?

  //list serial ports
  println("AVAILABLE SERIAL PORTS:");
  println(Serial.list());
  
  //give option of passing serial port number on command line
   if (props.getProperty("--serialport")!=null){
      portName=props.getProperty("--serialport");
   } else { 
      //cycle through ports and do matches 
      //may need to modify on final computer  
      for (int i=0; i<Serial.list().length; i++){  
        String[] m = match(Serial.list()[i],"(usbmodem)"); //arduino shows up as modem on mac
        String[] m2 = match(Serial.list()[i],"(COM3)");
        if ((m!=null) || (m2!=null)) {
          SERIAL_PORT_NUM = i;
          println(i + " " + Serial.list()[i]);
        }
      }
      portName = Serial.list()[SERIAL_PORT_NUM];  
   }
  
  println("  -> Using port " + SERIAL_PORT_NUM + ": " + portName);
  //open serial connection
  serial = new Serial(this, portName, SERIAL_PORT_BAUD_RATE);
  
  //setup base vlc url based on defaults/commandline
  if (props.getProperty("--defaultpass")!=null){
    defaultpass=props.getProperty("--defaultpass");
  }

  if (props.getProperty("--defaultport")!=null){
    defaultport=props.getProperty("--defaultport");
  }
  
  baseurl = "http://:" + defaultpass + "@localhost:" + defaultport + "/requests/status.json";
  println("baseurl for vlc commands: " + baseurl);
} 

void setupRazor() {
  println("Trying to setup and synch IMU...");

  // On Mac OSX and Linux (Windows too?) the board will do a reset when we connect, which is really bad.
  // See "Automatic (Software) Reset" on http://www.arduino.cc/en/Main/ArduinoBoardProMini
  // So we have to wait until the bootloader is finished and the Razor firmware can receive commands.
  // To prevent this, disconnect/cut/unplug the DTR line going to the board. This also has the advantage,
  // that the angles you receive are stable right from the beginning. 
  delay(3000);  // 3 seconds should be enough
  
  // Set IMU output parameters
  serial.write("#ob");  // Turn on binary output
  serial.write("#o1");  // Turn on continuous streaming output
  serial.write("#oe0"); // Disable error message output
  
  // Synch with IMU
  serial.clear();  // Clear input buffer up to here
  serial.write("#s00");  // Request synch token
}

float readFloat(Serial s) {
  // Convert from little endian (Razor) to big endian (Java) and interpret as float
  return Float.intBitsToFloat(s.read() + (s.read() << 8) + (s.read() << 16) + (s.read() << 24));
}

void draw() {
  background(0);

  //imu is synched when it returns a sync token
  if (!synched){
    if (frameCount == 2)
      setupRazor();  // Set ouput params and request synch token
    else if (frameCount > 2)
      synched = readToken(serial, "#SYNCH00\r\n");  // Look for synch token

    // Reset scene
    pg_reset();
    background(0);
    return;
  }

  // Read angles from serial port 
  //( they come in binary yaw/pitch/roll as binary float, so one output frame is 3x4 = 12 bytes long )
  while (serial.available() >= 12) {
    yaw = readFloat(serial);
    pitch = readFloat(serial);
    roll = readFloat(serial);
  }

  //println((float) yaw, (float) pitch, (float) roll);
  
  float y = yaw - yawOffset;
  float p = pitch - pitchOffset;
  float r = roll - rollOffset;

  norm_vals = new FloatList();
  norm_vals.append(y);
  norm_vals.append(p);
  norm_vals.append(r);

 // Output angles
  textFont(f,20);
  pushMatrix();
  textAlign(LEFT);
  fill(255);
  text("Yaw: " + nfs(y, 3,3), 5, height - 110);
  text("Pitch: " + nfs(p,3,3), 155, height - 110);
  text("Roll: " + nfs(r,3,3), 305, height - 110);
  popMatrix();

  float yPlot = map(y, -40, 40, 0, height);
  float pPlot = map(p, -40, 40, 0, height);
  float rPlot = map(r, -40, 40, 0, height);

    pg.beginDraw();
    
    pushMatrix();
     pg.strokeWeight(2);
     // draw the line:
     pg.stroke(207,0,15);
     pg.line(xPos-1, constrain((height - lastY),0,height), xPos, constrain((height - yPlot),0,height));
     //pg.line(xPos-1, height - lastY, xPos, height - yPlot);
     //pg.point(xPos,height-yPlot);
     
     pg.stroke(58,83,155);
     pg.line(xPos-1, constrain((height - lastP),0,height), xPos, constrain((height - pPlot),0,height));
     //pg.line(xPos-1, height - lastP, xPos, height - pPlot);
     //pg.point(xPos,height-pPlot);

     pg.stroke(27,188,155);
     pg.line(xPos-1, constrain((height - lastR),0,height), xPos, constrain((height - rPlot),0,height));
     //pg.line(xPos-1, height - lastR, xPos, height - rPlot);
     //pg.point(xPos,height-rPlot);

  //trigger alert
  if (((abs(norm_vals.max()) >= slider.getValue()) || (abs(norm_vals.min()) >= slider.getValue())) && (doAlert)) {
    boxColor=warnColor;
    pg.stroke(189,195,199,40);
    pg.line(xPos, 0, xPos, height);
  } else {
    boxColor = bgColor; 
  }

    popMatrix();
    pg.endDraw();
    image(pg,5,5);
    
     //update last, for drawing line
     lastY = yPlot;
     lastP = pPlot;
     lastR = rPlot;
    
     // at the edge of the screen, go back to the beginning:
     if (xPos >= width) {
       //reset the horizontal pos
       xPos = 0;
       
       //auto center the lines
       if(doLevel){
         yawOffset = yaw;
         pitchOffset = pitch;
         rollOffset = roll;
       }
       
       //reset/clear the plot screen       
       pg_reset();
     } else {
       // increment the horizontal position:
       xPos++;
     }

  //trigger alert
  if (((abs(norm_vals.max()) >= slider.getValue()) || (abs(norm_vals.min()) >= slider.getValue())) && (doAlert)) {
    boxColor=warnColor;
    
    //if ( (doPause) && (!isPaused) && ( (millis() - pauseTime)>pauseDur) ){
    if ( (doPause) && (!isPaused) ){
     String url = baseurl + "?command=pl_pause";
     vlc_control(url);
     pauseTime = millis();
     isPaused = true;
    }
    
  } else {
    boxColor=bgColor; 
  }
  
  if (alertBox.getColor().getBackground() != color(boxColor)){
    alertBox.setColorBackground(boxColor);
  }
  
  
  //unpause if longer than duration and not still moving
  if ((isPaused) && ((millis() - pauseTime)>pauseDur) && (boxColor!=warnColor) ){
     String url = baseurl + "?command=pl_pause";
     vlc_control(url);
     pauseTime = millis();
     isPaused = false;
  }
  
  
}

//do this loop if anything happens with buttons
//void controlEvent(ControlEvent theEvent) {
//  if (theEvent.isFrom(checkbox)) {
//    print("got an event from "+checkbox.getName()+"\t\n");
//    // checkbox uses arrayValue to store the state of 
//    // individual checkbox-items. usage:
//    println(checkbox.getArrayValue());
//    for (int i=0; i<checkbox.getArrayValue().length;i++){
//      int cval=(int)checkbox.getArrayValue()[i];
//      print(cval);
//      if(cval==1) {
//        boxColor = warnColor;
//      } else {
//        boxColor = bgColor;
//      }
//    }
//  
//    println();    
//  } else if ( theEvent.isFrom(slider)) {
//    print("got an event from "+slider.getName()+"\t\n");
//    println(slider.getValue());
//    if (slider.getValue() != slideVal){
//      slideVal = slider.getValue(); 
//    }   
//  }
//    println("something");
//}

void slideVal(float degreeVal){
  println(degreeVal);
}

//turn on/off the alerts
void alert(boolean togFlag){
  doAlert = (togFlag==true) ? true : false;
}

//turn on/off the leveling
void level(boolean togFlag){
  doLevel = (togFlag==true) ? true : false;
}

//turn on/off the vlc control
void pause(boolean togFlag){
  doPause = (togFlag==true) ? true : false;
  if ( (doPause) && (toggle.getState() != true) ){
    toggle.setState(true);
    doAlert = true;
  }
}

void pg_reset() {
 pg.beginDraw();
 pg.background(0);
 pg.endDraw();
 image(pg,5,5);
}


//send http request to vlc
void vlc_control(String url) {
  HttpGet method = new HttpGet(url);
  println("sending: " + url);
  
  try{
  response = client.execute(method);
  entity = response.getEntity();
  if (null != entity){
       String retSrc = EntityUtils.toString(entity);
       //println(retSrc);
       JSON vlc_obj = JSON.parse(retSrc);
       //println(vlc_obj.getString("state"));
       //isPaused = (vlc_obj.getString("state") == "paused") ? true : false; 
    }    
  } catch(java.net.ConnectException e) {
    println("could not connect to VLC player.  http interface must be configured");
    println("expecting VLC web interface at localhost port " + defaultport + " with password " + defaultpass);
    println(e);
    println("turn off VLC pausing");
    toggle3.setState(false);
  } catch(Exception e) {
     println(e);
  //} finally {
  //  client.getConnectionManager().shutdown();     
  }
}

Properties loadCommandLine() {
  Properties props = new Properties();
  for (String arg:args) {
    String[] parsed = arg.split("=", 2);
    if (parsed.length == 2)
      props.setProperty(parsed[0], parsed[1]);
  }
  return props;
}

void keyPressed() {
  switch(key) {
    case('a'):
    println("aligning YPR to current");
    yawOffset = yaw;
    pitchOffset = pitch;
    rollOffset = roll;
    break;

    case('p'):
    String url = baseurl + "?command=pl_pause";
    vlc_control(url);
    pauseTime = millis();
    isPaused = false;
    break;
    
    case('n'):
    String url2 = baseurl + "?command=pl_next";
    vlc_control(url2);
    break;
  }
  
}


