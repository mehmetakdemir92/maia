//
//  LegalDocumentView.swift
//  maia
//

import SwiftUI

enum LegalDocumentType: Hashable, Identifiable {
    case terms
    case privacy
    case subscription

    var id: String { title }

    var title: String {
        switch self {
        case .terms: return String(localized: "Terms of Use")
        case .privacy: return String(localized: "Privacy Policy")
        case .subscription: return String(localized: "Subscription Terms")
        }
    }

    var bodyText: String {
        switch self {
        case .terms:
            return String(localized: String.LocalizationValue(
"""
KULLANIM KOSULLARI

Maia uygulamasini kullanarak bu kosullari kabul etmis sayilirsiniz.

1) Hesap ve guvenlik
- Hesap bilgilerinizin guvenliginden siz sorumlusunuz.
- Hesabinizin yetkisiz kullanimini fark etmeniz halinde bize bildirmeniz gerekir.

2) Izin verilen kullanim
- Uygulama yalnizca hukuka uygun ve egitim amacli kullanilabilir.
- Sisteme yetkisiz erisim, hizmeti bozma girisimi veya tersine muhendislik yasaktir.

3) Ucretli ozellikler ve abonelik
- Premium icerikler abonelik kapsaminda sunulabilir.
- Ucretlendirme, yenileme ve iptal surecleri Apple App Store tarafindan yonetilir.

4) Degisiklik hakki
- Uygulama ozellikleri ve bu kosullar zaman zaman guncellenebilir.
- Onemli degisiklikler uygulama icinden duyurulur.

5) Sorumlulugun sinirlandirilmasi
- Uygulama "oldugu gibi" sunulur.
- Yasal olarak izin verilen olcude, dolayli zararlar ve hizmet kesintilerinden sorumluluk kabul edilmez.

6) Iletisim
- Hukuki konular icin: support@yourdomain.com
"""
            ))
        case .privacy:
            return String(localized: String.LocalizationValue(
"""
GIZLILIK POLITIKASI

Bu politika, Maia'nin hangi verileri hangi amaclarla isledigini aciklar.

1) Islenen veri kategorileri
- Hesap verileri (e-posta, kullanici kimligi)
- Uygulama kullanim ve teknik verileri (analitik, hata kayitlari)
- Abonelik ve yetki durum bilgileri

2) Isleme amaclari
- Giris islemlerini ve temel uygulama ozelliklerini saglamak
- Guvenlik, performans ve urun kalitesini iyilestirmek
- Premium ozellikleri sunmak

3) Ucuncu taraf hizmetler
- Kimlik dogrulama, depolama ve analitik icin Firebase/Google servisleri kullanilabilir.

4) Veri saklama
- Veriler, isleme amaci icin gerekli sure boyunca saklanir.
- Yasal zorunluluk yoksa silme talepleri dogrultusunda kaldirilir veya anonimlestirilir.

5) Kullanici haklari
- Uygulanabilir mevzuata gore erisim, duzeltme ve silme taleplerinde bulunabilirsiniz.

6) Iletisim
- Gizlilik talepleri icin: privacy@yourdomain.com
"""
            ))
        case .subscription:
            return String(localized: String.LocalizationValue(
"""
ABONELIK KOSULLARI

- Satin alma onayinda odeme Apple ID hesabiniza yansitilir.
- Abonelik, mevcut donem bitiminden en az 24 saat once iptal edilmezse otomatik yenilenir.
- Yenileme ucreti, mevcut donemin bitimine 24 saat kala hesabiniza yansitilabilir.
- Abonelik yonetimi ve iptal islemleri App Store hesap ayarlarindan yapilir.
- Sunulmasi halinde ucretsiz deneme suresi, sure sonunda iptal edilmezse ucretli abonelige donusur.
"""
            ))
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocumentType

    var body: some View {
        ScrollView {
            Text(document.bodyText)
                .font(.body)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
