import datetime
def get_month_date():
  current_date = datetime.date.today()
  month = current_date.month
  day = current_date.day
  return month, day