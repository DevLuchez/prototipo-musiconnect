package musiconnect.com.prototipo_musiconnect

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Canal das notificações (novas para você + prazos dos favoritos) —
        // o nome aparece nas configurações de notificação do Android. O id é
        // o mesmo do default_notification_channel_id no AndroidManifest.xml.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "oportunidades",
                "Oportunidades e prazos",
                NotificationManager.IMPORTANCE_DEFAULT,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
