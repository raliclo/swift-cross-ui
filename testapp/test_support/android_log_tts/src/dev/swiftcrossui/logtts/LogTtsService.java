package dev.swiftcrossui.logtts;

import android.media.AudioFormat;
import android.speech.tts.SynthesisCallback;
import android.speech.tts.SynthesisRequest;
import android.speech.tts.TextToSpeech;
import android.speech.tts.TextToSpeechService;
import android.util.Log;

/**
 * A text-to-speech engine that speaks nothing and logs everything it is asked to say.
 *
 * <p>Made the device's default engine, it receives every utterance a screen reader produces --
 * TalkBack speaks through the default engine -- so `adb logcat -s SCUI-TTS` is a transcript of
 * what a user would hear. That turns "someone has to listen" into a check a script can make.
 *
 * <p>一個什麼都不唸、但把被要求唸的每一段都記下來的 TTS 引擎。設為裝置的預設引擎後,它會收到螢幕閱讀器產生的
 * 每一段朗讀——TalkBack 經由預設引擎發聲——所以 `adb logcat -s SCUI-TTS` 就是使用者會聽到的內容的逐字稿。
 * 「要有人聽」因此變成一個腳本做得到的檢查。
 */
public class LogTtsService extends TextToSpeechService {
    private static final String TAG = "SCUI-TTS";
    private String[] language = {"eng", "USA", ""};

    @Override
    protected int onIsLanguageAvailable(String lang, String country, String variant) {
        return TextToSpeech.LANG_COUNTRY_AVAILABLE;
    }

    @Override
    protected String[] onGetLanguage() {
        return language;
    }

    @Override
    protected int onLoadLanguage(String lang, String country, String variant) {
        language = new String[] {lang, country, variant};
        return TextToSpeech.LANG_COUNTRY_AVAILABLE;
    }

    @Override
    protected void onStop() {}

    @Override
    protected void onSynthesizeText(SynthesisRequest request, SynthesisCallback callback) {
        CharSequence text = request.getCharSequenceText();
        Log.i(TAG, "SPEAK: " + (text == null ? request.getText() : text.toString()));
        // A short silence, so the caller sees a normal, finished utterance.
        // 一小段靜音,讓呼叫端看到的是一次正常、已完成的朗讀。
        int rate = 16000;
        callback.start(rate, AudioFormat.ENCODING_PCM_16BIT, 1);
        byte[] silence = new byte[rate / 10 * 2];
        callback.audioAvailable(silence, 0, silence.length);
        callback.done();
    }
}
