package com.htetznaing.adbotg;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Color;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;

import androidx.annotation.NonNull;
//import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;

import android.os.Looper;
import android.util.Log;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.RelativeLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull; //added

import com.cgutman.adblib.AdbBase64;
import com.cgutman.adblib.AdbConnection;
import com.cgutman.adblib.AdbCrypto;
import com.cgutman.adblib.AdbStream;
import com.cgutman.adblib.UsbChannel;

import java.io.File;
import java.io.IOException; //added
import java.io.ByteArrayOutputStream;
import java.io.UnsupportedEncodingException;
import static com.htetznaing.adbotg.Message.CONNECTING;
import static com.htetznaing.adbotg.Message.DEVICE_FOUND;
import static com.htetznaing.adbotg.Message.DEVICE_NOT_FOUND;
import static com.htetznaing.adbotg.Message.FLASHING;
import static com.htetznaing.adbotg.Message.INSTALLING_PROGRESS;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;


public class MainActivity extends FlutterActivity{
    private Handler handler;
    private UsbDevice mDevice;
    private AdbCrypto adbCrypto;
    private AdbConnection adbConnection;
    private UsbManager mManager;
    private AdbStream stream;
    private MethodChannel flutterChannel;
    private static final String CHANNEL = "com.htetznaing.adbotg/usb"; //added
    private boolean isConnected = false;// added, used to monitor connect status

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // 系统服务获取 USB 管理器
        mManager = (UsbManager) getSystemService(Context.USB_SERVICE);

        handler = new Handler(Looper.getMainLooper()) {
            @Override
            public void handleMessage(@NonNull android.os.Message msg) {
                switch (msg.what) {
                    case DEVICE_FOUND:
                        Log.i("ADB_OTG", ">> handler: received DEVICE_FOUND message." +
                                "start initialize Shell");
                        initCommand();
                        try {
                            flutterChannel.invokeMethod("onStatus", "connected");
                            isConnected = true;
                        } catch (Exception ignored) {}
                        Log.i("ADB_OTG", "Init command done.");
                        break;

                    case CONNECTING:
                        try {
                            isConnected = false;
                            flutterChannel.invokeMethod("onStatus", "connecting");
                        } catch (Exception ignored) {}
                        break;

                    case DEVICE_NOT_FOUND:
                        try {
                            isConnected = false;
                            flutterChannel.invokeMethod("onStatus", "disconnected");
                        } catch (Exception ignored) {}
                        break;

                    case FLASHING:
                        Toast.makeText(MainActivity.this, "Flashing", Toast.LENGTH_SHORT).show();
                        break;

                    case INSTALLING_PROGRESS:
                        Toast.makeText(MainActivity.this, "Progress", Toast.LENGTH_SHORT).show();
                        break;

                }
            }
        };

        AdbBase64 base64 = new MyAdbBase64();
        try {
            adbCrypto = AdbCrypto.loadAdbKeyPair(base64, new File(getFilesDir(), "private_key"), new File(getFilesDir(), "public_key"));
        } catch (Exception e) {
            e.printStackTrace();
        }

        if (adbCrypto == null) {
            try {
                adbCrypto = AdbCrypto.generateAdbKeyPair(base64);
                adbCrypto.saveAdbKeyPair(new File(getFilesDir(), "private_key"), new File(getFilesDir(), "public_key"));
            } catch (Exception e) {
                Log.w(Const.TAG, "fail to generate and save key-pair", e);
            }
        }

        IntentFilter filter = new IntentFilter();
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        // 加入第二个监听项：自定义的 USB 权限广播事件，来源是UsbReceiver
        filter.addAction(Message.USB_PERMISSION);
        //调用 registerReceiver 注册接收器，告诉系统：
        //用 mUsbReceiver 处理；匹配 filter 中的事件；RECEIVER_NOT_EXPORTED：只允许 应用内部广播，不能被其他 app 调用（安全）
        ContextCompat.registerReceiver(this, mUsbReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED);

        //Check USB
        UsbDevice device = getIntent().getParcelableExtra(UsbManager.EXTRA_DEVICE);
        if (device!=null) {
            System.out.println("From Intent!");
            asyncRefreshAdbConnection(device);
        }else {
            System.out.println("From onCreate!");
            for (String k : mManager.getDeviceList().keySet()) {
                UsbDevice usbDevice = mManager.getDeviceList().get(k);
                handler.sendEmptyMessage(CONNECTING);
                if (mManager.hasPermission(usbDevice)) { ;
                    asyncRefreshAdbConnection(usbDevice);
                } else {
                    mManager.requestPermission(
                            usbDevice,
                            PendingIntent.getBroadcast(getApplicationContext(),
                                    0,
                                    new Intent(Message.USB_PERMISSION),
                                    PendingIntent.FLAG_IMMUTABLE));
                }
            }
        }
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        Log.i("ADB_OTG", "configureFlutterEngine running");
        mManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        loadOrGenerateKeys();

        flutterChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                CHANNEL
        );
        flutterChannel.setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "requestConnection":
                            requestUsbConnection();
                            result.success(null);
                            break;
                        case "runCommand":
                            String runcmd = call.argument("command");
                            String output = runAdbCommand(runcmd);
                            result.success(output);
                            break;

                        case "sendCommand":
                            String sendcmd = call.argument("command");
                            // 这里直接写入到那个已打开的 interactive shell
                            putCommand(sendcmd);
                            result.success(null);
                            break;

                        case "isConnected":
                            result.success(isConnected); // return isConnected
                            break;

                        default:
                            result.notImplemented();
                    }
                });
    }

    private String runAdbCommand(String command) {
        try {
            // Open a one-off shell stream for this single command
            AdbStream shell = adbConnection.open("shell:" + command);
            StringBuilder sb = new StringBuilder();

            // Read until the stream closes or returns empty
            while (!shell.isClosed()) {
                byte[] data = shell.read();        // no args here!
                if (data == null || data.length == 0) break;
                sb.append(new String(data, "UTF-8"));
            }
            shell.close();
            return sb.toString();
        } catch (Exception e) {
            return "Error: " + e.getMessage();
        }
    }

    private void safeInvokeStatus(String status) {
        if (flutterChannel != null) {
            flutterChannel.invokeMethod("onStatus", status);
        }
    }

    private void loadOrGenerateKeys() {
        AdbCrypto base;
        try {
            adbCrypto = AdbCrypto.loadAdbKeyPair(
                    new MyAdbBase64(),
                    new File(getFilesDir(), "private_key"),
                    new File(getFilesDir(), "public_key")
            );
        } catch (Exception e) {
            try {
                adbCrypto = AdbCrypto.generateAdbKeyPair(new MyAdbBase64());
                adbCrypto.saveAdbKeyPair(
                        new File(getFilesDir(), "private_key"),
                        new File(getFilesDir(), "public_key")
                );
            } catch (Exception ex) {
                ex.printStackTrace();
            }
        }
    }

    private void requestUsbConnection() {
        // 注册广播监听权限和插拔
        IntentFilter filter = new IntentFilter();
        filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        filter.addAction(Message.USB_PERMISSION);
        ContextCompat.registerReceiver(this, mUsbReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED);

        // 主动扫描已插设备并请求权限
        for (UsbDevice device : mManager.getDeviceList().values()) {
            if (mManager.hasPermission(device)) {
                asyncRefreshAdbConnection(device);
            } else {
                PendingIntent pi = PendingIntent.getBroadcast(
                        getApplicationContext(), 0,
                        new Intent(Message.USB_PERMISSION),
                        PendingIntent.FLAG_IMMUTABLE
                );
                mManager.requestPermission(device, pi);
            }
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        System.out.println("From onNewIntent");
        asyncRefreshAdbConnection((UsbDevice) intent.getParcelableExtra(UsbManager.EXTRA_DEVICE));
    }

    public void asyncRefreshAdbConnection(final UsbDevice device) {
        if (device != null) {
            new Thread() {
                @Override
                public void run() {
                    final UsbInterface intf = findAdbInterface(device);
                    try {
                        setAdbInterface(device, intf);
                    } catch (Exception e) {
                        Log.w(Const.TAG, "setAdbInterface(device, intf) fail", e);
                    }
                }
            }.start();
        }
    }

    BroadcastReceiver mUsbReceiver = new BroadcastReceiver() {
        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            Log.d(Const.TAG, "mUsbReceiver onReceive => "+action);
            if (UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) {
                isConnected = false; // added
                UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                String deviceName = device.getDeviceName();
                if (mDevice != null && mDevice.getDeviceName().equals(deviceName)) {
                    try {
                        Log.d(Const.TAG, "setAdbInterface(null, null)");
                        setAdbInterface(null, null);
                    } catch (Exception e) {
                        Log.w(Const.TAG, "setAdbInterface(null,null) failed", e);
                    }
                }
            } else if (Message.USB_PERMISSION.equals(action)){
                System.out.println("From receiver!");
                UsbDevice usbDevice = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                handler.sendEmptyMessage(CONNECTING);
                if (mManager.hasPermission(usbDevice))
                    asyncRefreshAdbConnection(usbDevice);
                else
                    mManager.requestPermission(usbDevice,PendingIntent.getBroadcast(getApplicationContext(), 0, new Intent(Message.USB_PERMISSION), PendingIntent.FLAG_IMMUTABLE));
            } else if (UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action) // added
                    || Message.USB_PERMISSION.equals(action)) {
                // 设备插入或者用户在弹窗中授权后，统一走这段
                UsbDevice usbDevice = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                handler.sendEmptyMessage(CONNECTING);
                if (mManager.hasPermission(usbDevice)) {
                    asyncRefreshAdbConnection(usbDevice);
                } else {
                    PendingIntent pi = PendingIntent.getBroadcast(
                            context,
                            0,
                            new Intent(Message.USB_PERMISSION),
                            PendingIntent.FLAG_IMMUTABLE
                    );
                    mManager.requestPermission(usbDevice, pi);
                }
            }
        }
    };

    // searches for an adb interface on the given USB device
    private UsbInterface findAdbInterface(UsbDevice device) {
        int count = device.getInterfaceCount();
        for (int i = 0; i < count; i++) {
            UsbInterface intf = device.getInterface(i);
            // 遍历一个 USB 设备上所有的接口 (UsbInterface)
            // 只要有一个接口的 class/subclass/protocol 分别为 255/66/1
            // 就认为它是 ADB 通信接口，返回它。
            if (intf.getInterfaceClass() == 255 && intf.getInterfaceSubclass() == 66 &&
                    intf.getInterfaceProtocol() == 1) {
                return intf;
            }
        }
        return null;
    }

    // Sets the current USB device and interface

    //检查一下这部分
    private synchronized boolean setAdbInterface(UsbDevice device, UsbInterface intf) throws IOException, InterruptedException {
        if (adbConnection != null) {
            adbConnection.close();
            isConnected = false;
            adbConnection = null;
            mDevice = null;
        }

        if (device != null && intf != null) {
            UsbDeviceConnection connection = mManager.openDevice(device);
            if (connection != null) {
                if (connection.claimInterface(intf, false)) {
                    handler.sendEmptyMessage(CONNECTING);
                    adbConnection = AdbConnection.create(new UsbChannel(connection, intf), adbCrypto);
                    adbConnection.connect();
                    //TODO: DO NOT DELETE IT, I CAN'T EXPLAIN WHY
                    // 创建一个 shell 通道（类似打开 socket 端口）。
                    adbConnection.open("shell:exec date");

                    mDevice = device;
                    handler.sendEmptyMessage(DEVICE_FOUND);
                    Log.i("ADB_OTG", ">> DEVICE_FOUND");
                    return true;
                } else {
                    connection.close();
                }
            }
        }

        handler.sendEmptyMessage(DEVICE_NOT_FOUND);

        mDevice = null;
        return false;
    }

    @Override
    public void onResume() {
        super.onResume();
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        unregisterReceiver(mUsbReceiver);
        try {
            if (adbConnection != null) {
                adbConnection.close();
                isConnected = false;
                adbConnection = null;
            }
        } catch (IOException e) {
            e.printStackTrace();
        }

    }

    private void initCommand(){
        // Open the shell stream of ADB
        try {
            //用于执行自定义命令（用户在 UI 输入的）。
            stream = adbConnection.open("shell:");
        } catch (UnsupportedEncodingException e) {
            e.printStackTrace();
            return;
        } catch (IOException e) {
            e.printStackTrace();
            return;
        } catch (InterruptedException e) {
            e.printStackTrace();
            return;
        }

        // Start the receiving thread
        new Thread(new Runnable() {
            @Override
            public void run() {
                while (!stream.isClosed()) {
                    try {
                        byte[] data = stream.read();
                        if (data == null || data.length == 0) continue;
                        final String line = new String(data, "US-ASCII");
                        runOnUiThread(() -> {
                            flutterChannel.invokeMethod("onOutput", line);
                            // send signal to frontend to show the end of output
                            // flutterChannel.invokeMethod("onOutput", "__done__");
                        });
                    } catch (UnsupportedEncodingException e) {
                        e.printStackTrace();
                        return;
                    } catch (InterruptedException e) {
                        e.printStackTrace();
                        return;
                    } catch (IOException e) {
                        e.printStackTrace();
                        return;
                    }
                }
            }
        }).start();
    }

    // 直接向 interactive shell 写命令，不依赖任何 EditText
    private void putCommand(String cmd) {
        if (cmd == null || cmd.trim().isEmpty()) return;
        try {
            if (cmd.equalsIgnoreCase("exit")) {
                finish();
            } else {
                stream.write((cmd + "\n").getBytes("UTF-8"));
            }
        } catch (IOException | InterruptedException e) {
            e.printStackTrace();
        }
    }
}

