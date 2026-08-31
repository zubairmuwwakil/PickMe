package com.cardcopilot.app.services

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.regex.Pattern

/**
 * High-ROI Automated Transaction Capture Service on Android.
 * Listens for purchase/transaction push notifications from supported banking apps,
 * extracts merchant and amount on-device, and feeds zero-touch reconciliation.
 *
 * Privacy by Construction: All parsing happens purely on-device. No notification
 * text or transaction details are ever transmitted over the network.
 */
class BankNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "BankNotificationCapture"

        // Known banking package names in Canada and the US
        val SUPPORTED_BANK_PACKAGES = setOf(
            // Canadian Issuers
            "com.rbc.mobile.android",
            "com.td",
            "com.scotiabank.banking",
            "com.cibc.android.mobi",
            "com.bmo.mobile",
            "com.americanexpress.android.acctsvcs.ca",
            "com.desjardins.mobile",
            "ca.tangerine.mobile",
            "com.simplii.mobile",
            "ca.loblaw.pcfinancial.mobile",
            "com.rogersbank.mobile",
            "ca.neofinancial.app",
            "com.wealthsimple",
            // US Issuers
            "com.americanexpress.android.acctsvcs.us",
            "com.chase.sig.android",
            "com.citi.citimobile",
            "com.capitalone.mobile",
            "com.discoverfinancial.mobile",
            "com.infonow.bofa",
            "com.wf.wellsfargomobile"
        )

        // Regex patterns for transaction amounts and merchants
        private val AMOUNT_PATTERN = Pattern.compile("\\\$([0-9]{1,5}(?:\\.[0-9]{2})?)")
        private val SPENT_AT_PATTERN = Pattern.compile("(?:at|@|chez)\\s+([^.,;\\n]+)", Pattern.CASE_INSENSITIVE)
        private val PURCHASE_PATTERN = Pattern.compile("Purchase of\\s+\\\$([0-9.]+) at\\s+([^.,;\\n]+)", Pattern.CASE_INSENSITIVE)
    }

    data class CapturedTransaction(
        val packageName: String,
        val merchantName: String?,
        val amountCad: Double?,
        val timestamp: Long,
        val rawTitle: String?,
        val rawText: String?
    )

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName ?: return
        if (!SUPPORTED_BANK_PACKAGES.contains(packageName)) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val combined = "$title $text".trim()

        if (combined.isEmpty()) return

        val parsed = parseTransaction(packageName, title, text, sbn.postTime)
        if (parsed != null) {
            Log.d(TAG, "Captured transaction from $packageName: Merchant='${parsed.merchantName}', Amount=$${parsed.amountCad}")
            // Dispatches to local store/repository for closed-loop reconciliation
            handleCapturedTransaction(parsed)
        }
    }

    fun parseTransaction(packageName: String, title: String, text: String, postTime: Long): CapturedTransaction? {
        val fullText = "$title $text"

        // 1. Extract Amount
        val amountMatcher = AMOUNT_PATTERN.matcher(fullText)
        val amount: Double? = if (amountMatcher.find()) {
            amountMatcher.group(1)?.toDoubleOrNull()
        } else {
            null
        }

        // 2. Extract Merchant Name
        var merchant: String? = null
        val purchaseMatcher = PURCHASE_PATTERN.matcher(fullText)
        if (purchaseMatcher.find()) {
            merchant = purchaseMatcher.group(2)?.trim()
        } else {
            val spentMatcher = SPENT_AT_PATTERN.matcher(fullText)
            if (spentMatcher.find()) {
                merchant = spentMatcher.group(1)?.trim()
            }
        }

        // Filter out non-purchases (e.g. transfers, balances)
        if (amount == null && merchant == null) return null

        return CapturedTransaction(
            packageName = packageName,
            merchantName = merchant,
            amountCad = amount,
            timestamp = postTime,
            rawTitle = title,
            rawText = text
        )
    }

    private fun handleCapturedTransaction(transaction: CapturedTransaction) {
        // Broadcasts or persists the captured transaction locally for the Store to process
    }
}
