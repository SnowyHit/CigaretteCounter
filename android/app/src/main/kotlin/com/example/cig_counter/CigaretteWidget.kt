package com.example.cig_counter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.graphics.Color
import android.widget.Toast

class CigaretteWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == "com.example.cig_counter.LOG_CIGARETTE") {
            // Handle widget button click
            val sharedPref = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val today = java.text.SimpleDateFormat("yyyy-MM-dd").format(java.util.Date())
            val key = "flutter.$today"
            
            val currentCount = sharedPref.getInt(key, 0)
            sharedPref.edit().putInt(key, currentCount + 1).apply()
            
            // Notify the app
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, CigaretteWidget::class.java)
            )
            
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }
    }

    companion object {
        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            // Get today's count
            val sharedPref = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val today = java.text.SimpleDateFormat("yyyy-MM-dd").format(java.util.Date())
            val key = "flutter.$today"
            val count = sharedPref.getInt(key, 0)
            
            // Create an Intent for the button click
            val intent = Intent(context, CigaretteWidget::class.java).apply {
                action = "com.example.cig_counter.LOG_CIGARETTE"
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Build the widget UI
            val views = RemoteViews(context.packageName, R.layout.widget_cigarette)
            
            views.setTextViewText(R.id.widget_count, count.toString())
            views.setTextViewText(R.id.widget_label, "Logged Today")
            views.setOnClickPendingIntent(R.id.widget_button, pendingIntent)
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
