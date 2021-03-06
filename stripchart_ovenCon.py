import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math
import serial
import serial.tools.list_ports
import pandas

PORT = 'COM3'
try:
 ser.close();
except:
 print();
try:
 ser = serial.Serial(PORT, 115200, timeout=100)
except:
 print ('Serial port %s is not available' % PORT);
 portlist=list(serial.tools.list_ports.comports())
 print('Trying with port %s' % portlist[0][0]);
 ser = serial.Serial(portlist[0][0], 115200, timeout=100)
ser.isOpen()

xsize = 600

def data_gen():
    # I know we have to change this so that it plots my temperatures
    t = data_gen.t

    while True:
       out_str = ""
       strin = ser.readline();
       strin = strin.decode('ascii')
       if strin[0] != ' ':
            out_str += str(strin[0])
       if strin[1] != ' ':
            out_str += str(strin[1])
       if strin[2] != ' ':
            out_str += str(strin[2])
       if strin[3] != ' ':
             out_str += str(strin[3])
       if strin[4] != ' ':
             out_str += str(strin[4])
       newdata = int(out_str)
    #   newdata = newdata

       #print(newdata)
       t+=1
       val=newdata
       yield t, val

def run(data):
    # update the data
    t,y = data
    if t>-1:
        xdata.append(t)
        ydata.append(y)
        if t>xsize: # Scroll to the left.
            ax.set_xlim(t-xsize, t)
        line.set_data(xdata, ydata)

    return line,

def on_close_figure(event):
    sys.exit(0)

#main
out_str1 = ""
strin1 = ser.readline();
strin1 = strin1.decode('ascii')
if strin1[5] != ' ':
    out_str1 += str(strin1[5])
if strin1[6] != ' ':
    out_str1 += str(strin1[6])

data_for_colour = int(out_str1)

# graph is blue by default
graph = 'blue'
if data_for_colour == 1:
    graph = 'blue'
elif data_for_colour == 2:
    graph = 'green'
elif data_for_colour == 3:
    graph = 'red'
elif data_for_colour == 4:
    graph = 'yellow'
else:
    graph = 'blue'

data_gen.t = 1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
#sets the colour of the graph
line, = ax.plot([], [], lw=2, color=graph)
ax.set_ylim(-10, 400)
ax.set_xlim(0, xsize)
ax.grid()
xdata, ydata = [], []


# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
