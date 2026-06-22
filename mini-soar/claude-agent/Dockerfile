FROM python:3.11-slim
WORKDIR /app
COPY . .
RUN pip install flask groq python-dotenv
EXPOSE 8000
CMD ["python3", "app.py"]
