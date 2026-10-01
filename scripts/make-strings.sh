#!/usr/bin/env bash
# Builds App/FireWatchField/Resources/Localizable.xcstrings from the English → Turkish table
# below (NFR-7). Keys are the source strings exactly as Xcode extracts them: %lld for integers,
# %@ for strings, positional (%1$@) where Turkish reorders arguments.
# Usage: scripts/make-strings.sh
set -euo pipefail
cd "$(dirname "$0")/.."

table=$(cat <<'EOF'
%@ from you · tap to open	Sizden %@ uzakta · açmak için dokunun
%@ hotspot, %@, %@	%1$@ sıcak nokta, %2$@, %3$@
%lld h %lld min ago	%1$lld sa %2$lld dk önce
%lld hotspots, worst %@	%1$lld sıcak nokta, en kötüsü %2$@
%lld min ago	%lld dk önce
%lld waiting to send	%lld gönderilmeyi bekliyor
A hotspot flared up nearby	Yakında bir sıcak nokta yeniden alevlendi
A simulated wildfire near Manavgat plays on this phone. No network needed.	Manavgat yakınlarında simüle edilmiş bir orman yangını bu telefonda oynatılır. Ağ gerekmez.
About	Hakkında
Access token	Erişim anahtarı
Actions	İşlemler
Actions and reports wait on this phone and are sent when you turn this off, just as with real loss of signal.	İşlemler ve raporlar bu telefonda bekler ve bunu kapattığınızda gönderilir; gerçek sinyal kaybında olduğu gibi.
Add a photo	Fotoğraf ekle
Alert radius	Uyarı yarıçapı
Alerts	Uyarılar
Apply and restart	Uygula ve yeniden başlat
Assigned	Üstlenildi
Automatic	Otomatik
Confidence	Güven
Connecting…	Bağlanıyor…
Connects to the simulator server, for example one started with docker compose.	Simülatör sunucusuna bağlanır; örneğin docker compose ile başlatılmış olana.
Data	Veri
Data source	Veri kaynağı
Demo on this device	Bu cihazda demo
Details and actions	Ayrıntılar ve işlemler
Dismiss	Kapat
Drone %@, battery %lld percent	%1$@ dronu, pil yüzde %2$lld
Extinguished	Söndürüldü
Extreme	Aşırı
Filter	Filtre
Fire perimeter	Yangın sınırı
First seen	İlk görülme
Flare-ups	Yeniden alevlenmeler
Flared up	Yeniden alevlendi
From %@ to %@ over %lld readings	%3$lld ölçümde %1$@ değerinden %2$@ değerine
From you	Size uzaklık
Hand it back	Bırak
High	Yüksek
Hotspot	Sıcak nokta
Hotspot %@	Sıcak nokta %@
Hotspot no longer known	Bu sıcak nokta artık bilinmiyor
Hotspots	Sıcak noktalar
How bad	Ne kadar ciddi
Imperial (°F, mi)	İngiliz (°F, mil)
Last measured	Son ölçüm
Last measured %@	Son ölçüm %@
Live	Canlı
Location	Konum
Location of the sighting; move the map to adjust	Gözlemin konumu; ayarlamak için haritayı kaydırın
Low	Düşük
Map	Harita
Mark extinguished	Söndürüldü olarak işaretle
Metric (°C, km)	Metrik (°C, km)
Minimum severity	En düşük önem
Moderate	Orta
Move the map so the cross is on what you saw. It starts at your position.	Artıyı gördüğünüz yere getirmek için haritayı kaydırın. Konumunuzdan başlar.
New	Yeni
New %@ hotspot nearby	Yakında yeni %@ sıcak nokta
No hotspots	Sıcak nokta yok
No signal? Actions and reports wait on the phone and send later.	Sinyal yok mu? İşlemler ve raporlar telefonda bekler, sonra gönderilir.
Nothing matches the filter yet. Drones report new hotspots as they find them.	Henüz filtreye uyan bir şey yok. Dronlar yeni sıcak noktaları buldukça bildirir.
Offline · data from %@ · retry in %lld s	Çevrimdışı · veri %1$@ · %2$lld sn sonra yeniden denenecek
Offline · retry in %lld s	Çevrimdışı · %lld sn sonra yeniden denenecek
Perimeter time	Sınır zamanı
Photo	Fotoğraf
Remove the photo	Fotoğrafı kaldır
Replace the photo	Fotoğrafı değiştir
Replay speed	Oynatma hızı
Report	Rapor
Report saved. It is sent as soon as there's signal.	Rapor kaydedildi. Sinyal olur olmaz gönderilecek.
Saved on this device; it will sync when the connection allows.	Bu cihaza kaydedildi; bağlantı olduğunda eşitlenecek.
See hotspots that drones found, the fire's edge, and where the drones are.	Dronların bulduğu sıcak noktaları, yangının sınırını ve dronların yerini görün.
Send report	Raporu gönder
Server address	Sunucu adresi
Settings	Ayarlar
Severity	Önem
Show verified cold	Soğuk olduğu doğrulananları göster
Simulate no signal	Sinyal yokmuş gibi yap
Simulator server	Simülatör sunucusu
Smoke behind the ridge, flames, people at risk…	Sırtın arkasında duman, alevler, tehlikedeki insanlar…
Source code	Kaynak kodu
Start	Başla
Take this hotspot	Bu sıcak noktayı üstlen
Temperature	Sıcaklık
Temperature trend	Sıcaklık eğilimi
This is a demo: a simulated wildfire near Manavgat plays on this phone. Settings can connect to the simulator server instead.	Bu bir demo: Manavgat yakınlarında simüle edilmiş bir orman yangını bu telefonda oynatılır. Ayarlar'dan bunun yerine simülatör sunucusuna bağlanabilirsiniz.
Units	Birimler
Verified cold	Soğuk olduğu doğrulandı
Verify cold	Soğuk olduğunu doğrula
Version	Sürüm
Walking directions	Yürüyüş yol tarifi
What you see	Ne görüyorsunuz
Where	Nerede
Work hotspots from new to verified cold, most urgent first.	Sıcak noktaları yeniden soğuk olarak doğrulanana kadar işleyin; en acil olan önce.
Your %@ report, waiting to send	%@ raporunuz gönderilmeyi bekliyor
just now	az önce
seen %@	görülme: %@
EOF
)

{
    printf '{\n  "sourceLanguage" : "en",\n  "strings" : {\n'
    first=1
    while IFS=$'\t' read -r key value; do
        [ -n "$key" ] || continue
        [ $first -eq 1 ] || printf ',\n'
        first=0
        k=$(printf '%s' "$key" | sed 's/\\/\\\\/g; s/"/\\"/g')
        v=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '    "%s" : {\n      "localizations" : {\n        "tr" : {\n          "stringUnit" : {\n            "state" : "translated",\n            "value" : "%s"\n          }\n        }\n      }\n    }' "$k" "$v"
    done <<< "$table"
    printf '\n  },\n  "version" : "1.0"\n}\n'
} > App/FireWatchField/Resources/Localizable.xcstrings
echo "Wrote $(grep -c '"stringUnit"' App/FireWatchField/Resources/Localizable.xcstrings) Turkish strings"
