package dev.swiftcrossui.testapp;

import android.os.Bundle;

import androidx.appcompat.app.AppCompatActivity;

// The same activity Swift Bundler generated, in one fixed package for every
// app. libshim.so depends on lib<app>.so, so loading the shim loads the app.
// 與 Swift Bundler 所產生的相同，對每支 app 都放在同一個固定 package。libshim.so 依賴 lib<app>.so,
// 因此載入 shim 就載入了 app。
public class MainActivity extends AppCompatActivity {
    private native void setup();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        System.loadLibrary("shim");

        setup();
    }
}
