//
//  StreakView.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct StreakView: View {
    @EnvironmentObject var streakManager: StreakManager
    @State private var selectedMonth = Date()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Streak count in top right
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("\(streakManager.currentStreak)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.orange)
                        Text("Day Streak")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                .padding()
                
                // Calendar view
                CalendarView(selectedMonth: $selectedMonth)
                    .environmentObject(streakManager)
                
                Spacer()
            }
            .background(AppColors.background)
            .navigationTitle("Streak")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct CalendarView: View {
    @Binding var selectedMonth: Date
    @EnvironmentObject var streakManager: StreakManager
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    private var days: Int {
        getDaysInMonth(selectedMonth)
    }
    
    private var firstWeekday: Int {
        getFirstWeekday(of: selectedMonth)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Month selector
            HStack {
                Button(action: {
                    if let newMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) {
                        selectedMonth = newMonth
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(AppColors.primaryButton)
                }
                
                Spacer()
                
                Text(dateFormatter.string(from: selectedMonth))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    if let newMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) {
                        selectedMonth = newMonth
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(AppColors.primaryButton)
                }
            }
            .padding(.horizontal)
            
            // Calendar grid
            VStack(spacing: 8) {
                // Weekday headers
                HStack {
                    ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                // Calendar days
                ForEach(0..<6, id: \.self) { week in
                    HStack {
                        ForEach(0..<7, id: \.self) { day in
                            CalendarDayView(
                                week: week,
                                day: day,
                                firstWeekday: firstWeekday,
                                daysInMonth: days,
                                selectedMonth: selectedMonth,
                                streakManager: streakManager
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .background(AppColors.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .padding()
    }
    
    private func getDaysInMonth(_ date: Date) -> Int {
        let range = calendar.range(of: .day, in: .month, for: date)
        return range?.count ?? 0
    }
    
    private func getFirstWeekday(of date: Date) -> Int {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let firstDay = calendar.date(from: components) else { return 0 }
        return calendar.component(.weekday, from: firstDay) - 1
    }
    
    private func getDateForDay(_ day: Int, in month: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let firstDay = calendar.date(from: components),
              let date = calendar.date(byAdding: .day, value: day, to: firstDay) else {
            return Date()
        }
        return date
    }
}

struct CalendarDayView: View {
    let week: Int
    let day: Int
    let firstWeekday: Int
    let daysInMonth: Int
    let selectedMonth: Date
    @ObservedObject var streakManager: StreakManager
    
    private let calendar = Calendar.current
    
    private var dayIndex: Int {
        week * 7 + day
    }
    
    private var dayNumber: Int {
        dayIndex - firstWeekday + 1
    }
    
    private var isInMonth: Bool {
        dayIndex >= firstWeekday && dayIndex < firstWeekday + daysInMonth
    }
    
    private var date: Date {
        getDateForDay(dayIndex - firstWeekday, in: selectedMonth)
    }
    
    private var isCompleted: Bool {
        streakManager.isDayCompleted(date)
    }
    
    private var isToday: Bool {
        calendar.isDateInToday(date)
    }
    
    var body: some View {
        Group {
            if isInMonth {
                VStack {
                    Text("\(dayNumber)")
                        .font(.caption)
                        .foregroundColor(isToday ? .white : .primary)
                    
                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isToday ? AppColors.primaryButton : Color.clear)
                .cornerRadius(8)
            } else {
                Spacer()
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
        }
    }
    
    private func getDateForDay(_ day: Int, in month: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let firstDay = calendar.date(from: components),
              let date = calendar.date(byAdding: .day, value: day, to: firstDay) else {
            return Date()
        }
        return date
    }
}

#Preview {
    StreakView()
        .environmentObject(StreakManager())
}
