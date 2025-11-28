#!/bin/bash

set -e

################################################################################
# CONFIGURATION
################################################################################

PROJECT_DIR="/Users/YOUR_USERNAME/better_Live/LiveShowSite"
PROJECT_NAME="LiveShowSite"
APP_NAME="entertainment"
PYTHON_BIN="python3"
VENV_DIR="$PROJECT_DIR/venv"

# New: external locations (media and static live OUTSIDE the project folder)
EXTERNAL_BASE="/Users/YOUR_USERNAME/better_Live"
MEDIA_DIR="$EXTERNAL_BASE/media"
STATIC_DIR="$EXTERNAL_BASE/static"
VIDEO_THUMBS_DIR="$MEDIA_DIR/video_thumbnails"

################################################################################
# BACKUP DB AND DELETE OLD PROJECT
################################################################################

################################################################################
# SAFE BACKUP (timestamped) and DELETE OLD PROJECT
################################################################################

echo "==> Preparing safe backup..."

# Ensure EXTERNAL_BASE exists (should already)
mkdir -p "$EXTERNAL_BASE"

# Place backups *outside* the project/media/static trees, under EXTERNAL_BASE
BACKUP_ROOT="$EXTERNAL_BASE/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="$BACKUP_ROOT/backup_$TIMESTAMP"

# Make backup dir
mkdir -p "$BACKUP_DIR"

# Resolve absolute paths (best-effort)
# IMPORTANT: these `cd` calls assume EXTERNAL_BASE exists, which we created above.
ABS_PROJECT_DIR="$(cd "$(dirname "$PROJECT_DIR")" && pwd -P)/$(basename "$PROJECT_DIR")"
ABS_MEDIA_DIR="$(cd "$EXTERNAL_BASE" && cd "$(basename "$MEDIA_DIR")" >/dev/null 2>&1 && pwd -P || echo "$MEDIA_DIR")"
ABS_STATIC_DIR="$(cd "$EXTERNAL_BASE" && cd "$(basename "$STATIC_DIR")" >/dev/null 2>&1 && pwd -P || echo "$STATIC_DIR")"
ABS_BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd -P)"

# SAFETY CHECKS: refuse to run if backup dir would be inside project/media/static
case "$ABS_BACKUP_DIR" in
  "$ABS_PROJECT_DIR"*|"$ABS_MEDIA_DIR"*|"$ABS_STATIC_DIR"*)
    echo "ERROR: backup directory would be inside one of the source directories. Aborting to avoid recursion."
    echo "ABS_PROJECT_DIR: $ABS_PROJECT_DIR"
    echo "ABS_MEDIA_DIR:   $ABS_MEDIA_DIR"
    echo "ABS_STATIC_DIR:  $ABS_STATIC_DIR"
    echo "ABS_BACKUP_DIR:  $ABS_BACKUP_DIR"
    exit 1
    ;;
esac

echo "==> Backing up into: $BACKUP_DIR"

# Backup DB (if present)
if [ -f "$PROJECT_DIR/db.sqlite3" ]; then
    echo "==> Backing up existing db.sqlite3"
    cp -p "$PROJECT_DIR/db.sqlite3" "$BACKUP_DIR/db_backup.sqlite3"
fi

# Backup any project-local media (if present)
if [ -d "$PROJECT_DIR/media" ]; then
    echo "==> Backing up project media folder to $BACKUP_DIR/project_media"
    mkdir -p "$BACKUP_DIR/project_media"
    # rsync is safer; exclude any backups just in case
    rsync -a --delete --exclude="$BACKUP_ROOT" "$PROJECT_DIR/media/" "$BACKUP_DIR/project_media/"
fi

# Backup external media (if present)
if [ -d "$MEDIA_DIR" ]; then
    echo "==> Backing up external media folder to $BACKUP_DIR/media_external"
    mkdir -p "$BACKUP_DIR/media_external"
    rsync -a --delete --exclude="$BACKUP_ROOT" "$MEDIA_DIR/" "$BACKUP_DIR/media_external/"
fi

# Backup external static (if present)
if [ -d "$STATIC_DIR" ]; then
    echo "==> Backing up external static folder to $BACKUP_DIR/static_external"
    mkdir -p "$BACKUP_DIR/static_external"
    rsync -a --delete --exclude="$BACKUP_ROOT" "$STATIC_DIR/" "$BACKUP_DIR/static_external/"
fi

# Final safety: make sure BACKUP_DIR is not inside PROJECT_DIR before deletion
ABS_BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd -P)"
ABS_PROJECT_DIR="$(cd "$PROJECT_DIR/.." && pwd -P)/$(basename "$PROJECT_DIR")"
if [[ "$ABS_BACKUP_DIR" == "$ABS_PROJECT_DIR"* ]]; then
    echo "ERROR: backup directory is inside project directory (unsafe). Aborting delete."
    exit 1
fi

# Now remove old project safely
if [ -d "$PROJECT_DIR" ]; then
    echo "==> Removing old project directory: $PROJECT_DIR"
    rm -rf "$PROJECT_DIR"
fi


################################################################################
# CREATE VENV AND INSTALL DEPENDENCIES
################################################################################

echo "==> Creating virtual environment..."
$PYTHON_BIN -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "==> Installing Django + packages..."
pip install django django-allauth django-ckeditor moviepy pillow

################################################################################
# START DJANGO PROJECT AND APP
################################################################################

echo "==> Creating Django project and app..."
# Ensure the project directory exists (startproject will populate it)
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

django-admin startproject "$PROJECT_NAME" .
django-admin startapp "$APP_NAME"

# Create external media and static dirs (outside project)
mkdir -p "$MEDIA_DIR"
mkdir -p "$VIDEO_THUMBS_DIR"
mkdir -p "$STATIC_DIR"
# Ensure external static images folder exists
mkdir -p "$STATIC_DIR/images"
# Copy favicon and logo into preserved external static directory
if [ -f "$PROJECT_DIR/favicon.ico" ]; then
    cp "$PROJECT_DIR/favicon.ico" "$STATIC_DIR/images/favicon.ico"
fi

if [ -f "$PROJECT_DIR/favicon.png" ]; then
    cp "$PROJECT_DIR/favicon.png" "$STATIC_DIR/images/favicon.png"
fi

if [ -f "$PROJECT_DIR/logo.png" ]; then
    cp "$PROJECT_DIR/logo.png" "$STATIC_DIR/images/logo.png"
fi

################################################################################
# DJANGO SETTINGS.PY
################################################################################

SETTINGS_FILE="$PROJECT_DIR/$PROJECT_NAME/settings.py"
cat > "$SETTINGS_FILE" << 'EOF'
from pathlib import Path
import os

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = 'dev-secret-key'
# Generate real key and save it in a file as an Environmental Variable
DEBUG = True
# SET DEBUG = False in Production, 404 pages will be displayed instead of error msg.
ALLOWED_HOSTS = ['*']
# place the domain name above during production , disable hotlinks if desired

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    # Allauth
    'django.contrib.sites',
    'allauth',
    'allauth.account',
    'allauth.socialaccount',

    # CKEditor
    'ckeditor',
    'ckeditor_uploader',

    # Main app
    'entertainment',
]

SITE_ID = 1
LOGIN_REDIRECT_URL = '/'
LOGOUT_REDIRECT_URL = '/'

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',

    # REQUIRED FOR ALLAUTH
    'allauth.account.middleware.AccountMiddleware',

    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'LiveShowSite.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / "templates"],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'LiveShowSite.wsgi.application'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / "db.sqlite3",
    }
}

STATIC_URL = '/static/'
# Keep STATIC_ROOT inside project for collectstatic; static files to be served during develop come from external STATIC_DIR below
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_DIRS = [
    BASE_DIR / "static",
    r"{{STATIC_DIR}}",  # external static folder
]


MEDIA_URL = '/media/'
# Media live outside the project folder (external media dir)
MEDIA_ROOT = Path("/Users/YOUR_USERNAME/better_Live/media")

CKEDITOR_UPLOAD_PATH = "uploads/"
CKEDITOR_ALLOW_NONIMAGE_FILES = True
CKEDITOR_UPLOAD_PERMISSION = "entertainment.custom_ckeditor_upload_permission"
EOF

################################################################################
# MODELS
################################################################################

MODELS_FILE="$PROJECT_DIR/$APP_NAME/models.py"
cat > "$MODELS_FILE" << 'EOF'
from django.db import models
from django.contrib.auth.models import User
from ckeditor.fields import RichTextField

class Article(models.Model):
    title = models.CharField(max_length=200)
    content = RichTextField()
    author = models.ForeignKey(User, on_delete=models.CASCADE)
    created = models.DateTimeField(auto_now_add=True)
    image = models.ImageField(upload_to='article_images/', blank=True, null=True)

    def __str__(self):
        return self.title

class Photo(models.Model):
    caption = models.CharField(max_length=200)
    image = models.ImageField(upload_to='photos/')
    uploader = models.ForeignKey(User, on_delete=models.CASCADE)
    uploaded = models.DateTimeField(auto_now_add=True)

class Video(models.Model):
    title = models.CharField(max_length=200)
    video = models.FileField(upload_to='videos/')
    uploader = models.ForeignKey(User, on_delete=models.CASCADE)
    uploaded = models.DateTimeField(auto_now_add=True)
    thumbnail = models.ImageField(upload_to='video_thumbnails/', blank=True, null=True)
    custom_thumbnail = models.ImageField(upload_to='video_custom_thumbnails/', blank=True, null=True)

    def __str__(self):
        return self.title
EOF

################################################################################
# FORMS
################################################################################

FORMS_FILE="$PROJECT_DIR/$APP_NAME/forms.py"
cat > "$FORMS_FILE" << 'EOF'
from django import forms
from .models import Article, Photo, Video
from ckeditor.widgets import CKEditorWidget

class ArticleForm(forms.ModelForm):
    content = forms.CharField(widget=CKEditorWidget())
    class Meta:
        model = Article
        fields = ['title', 'content', 'image']

class PhotoForm(forms.ModelForm):
    class Meta:
        model = Photo
        fields = ['caption', 'image']

class VideoForm(forms.ModelForm):
    class Meta:
        model = Video
        fields = ['title', 'video', 'custom_thumbnail']
EOF

################################################################################
# VIEWS
################################################################################

VIEWS_FILE="$PROJECT_DIR/$APP_NAME/views.py"
cat > "$VIEWS_FILE" << 'EOF'
import os
import subprocess
from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.http import HttpResponseForbidden
from .models import Article, Photo, Video
from .forms import ArticleForm, PhotoForm, VideoForm
from django.core.paginator import Paginator
from django.conf import settings
from django.template import TemplateDoesNotExist
from django.http import Http404

def home(request):
    articles = Article.objects.order_by('-created')
    photos = Photo.objects.order_by('-uploaded')
    videos = Video.objects.order_by('-uploaded')

    paginator = Paginator(articles, 5)
    page = request.GET.get('page')
    articles_page = paginator.get_page(page)

    return render(request, 'home.html', {
        'articles': articles_page,
        'photos': photos,
        'videos': videos,
    })

def article_detail(request, pk):
    article = get_object_or_404(Article, pk=pk)
    return render(request, 'article_detail.html', {'article': article})

@login_required
def create_article(request):
    if request.method == 'POST':
        form = ArticleForm(request.POST, request.FILES)
        if form.is_valid():
            a = form.save(commit=False)
            a.author = request.user
            a.save()
            return redirect('home')
    else:
        form = ArticleForm()
    return render(request, 'create_article.html', {'form': form})

@login_required
def edit_article(request, pk):
    article = get_object_or_404(Article, pk=pk)
    if article.author != request.user:
        return HttpResponseForbidden()
    if request.method == 'POST':
        form = ArticleForm(request.POST, request.FILES, instance=article)
        if form.is_valid():
            form.save()
            return redirect('home')
    else:
        form = ArticleForm(instance=article)
    return render(request, 'edit_article.html', {'form': form, 'article': article})

@login_required
def delete_article(request, pk):
    article = get_object_or_404(Article, pk=pk)
    if article.author != request.user:
        return HttpResponseForbidden()
    article.delete()
    return redirect('home')

@login_required
def upload_photo(request):
    if request.method == 'POST':
        form = PhotoForm(request.POST, request.FILES)
        if form.is_valid():
            p = form.save(commit=False)
            p.uploader = request.user
            p.save()
            return redirect('home')
    else:
        form = PhotoForm()
    return render(request, 'upload_photo.html', {'form': form})

@login_required
def delete_photo(request, pk):
    photo = get_object_or_404(Photo, pk=pk)
    if photo.uploader != request.user:
        return HttpResponseForbidden()
    photo.delete()
    return redirect('home')

@login_required
def upload_video(request):
    if request.method == 'POST':
        form = VideoForm(request.POST, request.FILES)
        if form.is_valid():
            v = form.save(commit=False)
            v.uploader = request.user
            v.save()

            # Use custom thumbnail if provided
            if v.custom_thumbnail:
                v.thumbnail = v.custom_thumbnail
                v.save()
            else:
                # Auto-generate thumbnail
                input_file = v.video.path
                output_file = os.path.join(settings.MEDIA_ROOT, "video_thumbnails", f"thumb_{v.pk}.jpg")

                os.makedirs(os.path.dirname(output_file), exist_ok=True)

                try:
                    subprocess.run([
                        "ffmpeg",
                        "-i", input_file,
                        "-ss", "00:00:01",
                        "-vframes", "1",
                        "-vf", "scale=320:-1",
                        output_file
                    ], check=True)

                    rel_path = f"video_thumbnails/thumb_{v.pk}.jpg"
                    v.thumbnail = rel_path
                    v.save()

                except Exception as e:
                    print("Thumbnail generation failed:", e)

            return redirect('home')
    else:
        form = VideoForm()
    return render(request, 'upload_video.html', {'form': form})

@login_required
def delete_video(request, pk):
    video = get_object_or_404(Video, pk=pk)
    if video.uploader != request.user:
        return HttpResponseForbidden()
    video.delete()
    return redirect('home')

def custom_ckeditor_upload_permission(user):
    return user.is_authenticated 

def static_page(request, page):
    try:
        return render(request, f"static_pages/{page}.html")
    except TemplateDoesNotExist:
        raise Http404("Page not found")

EOF

################################################################################
# URLS
################################################################################
URLS_FILE="$PROJECT_DIR/LiveShowSite/urls.py"
cat > "$URLS_FILE" << 'EOF'
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from entertainment import views

urlpatterns = [
    path('admin/', admin.site.urls),

    path('accounts/', include('allauth.urls')),

    path('', views.home, name='home'),
    path('article/<int:pk>/', views.article_detail, name='article_detail'),
    path('article/create/', views.create_article, name='create_article'),
    path('article/<int:pk>/edit/', views.edit_article, name='edit_article'),
    path('article/<int:pk>/delete/', views.delete_article, name='delete_article'),

    path('photo/upload/', views.upload_photo, name='upload_photo'),
    path('photo/<int:pk>/delete/', views.delete_photo, name='delete_photo'),

    path('video/upload/', views.upload_video, name='upload_video'),
    path('video/<int:pk>/delete/', views.delete_video, name='video_delete'),

    path('ckeditor/', include('ckeditor_uploader.urls')),
    path('about/', views.static_page, {"page": "about"}, name="about"),
    path('contact/', views.static_page, {"page": "contact"}, name="contact"),
    path('selected_vids/', views.static_page, {"page": "selected_vids"}, name="selected_vids"),
    path('fav_pics/', views.static_page, {"page": "fav_pics"}, name="fav_pics"),
    path('page/<str:page>/', views.static_page, name='static_page'),
]

    


if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
EOF

################################################################################
# TEMPLATES
################################################################################

mkdir -p "$PROJECT_DIR/templates"

### BASE TEMPLATE
cat > "$PROJECT_DIR/templates/base.html" << 'EOF'
{% load static %}
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>EarthLight Magazine</title>

  <!-- Bootstrap CSS -->
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">

  <!-- Favicon -->
  <link rel="icon" href="{% static 'images/favicon.ico' %}" type="image/x-icon">
  <link rel="shortcut icon" href="{% static 'images/favicon.ico' %}" type="image/x-icon">

  <!-- Custom CSS -->
  <style>
  body::before {
  content: "";
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-image: url("{% static 'images/earth.jpg' %}");
  background-size: cover;
  background-position: center;
  background-repeat: no-repeat;
  opacity: 0.18;          /* adjust translucency here */
  z-index: -1;            /* behind all content */
}


    /* Images inside cards, articles, and content scale properly */
    .card-img-top,
    .article-content img,
    .recent-photos img,
    .main-content img {
      width: 100%;
      height: auto !important;
      object-fit: contain !important;
    }

    /* Logo styling */
    .navbar-brand img.site-logo {
      max-height: 50px;
      width: auto;
      margin-right: 8px;
      object-fit: contain;
    }

    /* Card image tweak for cover effect */
    .card-img-top { object-fit: cover; }

    /* Video card background */
    .video-card .ratio { background: #000; }

    /* Footer styling */
    footer {
      font-size: 0.9rem;
      color: #6c757d;
      padding: 1rem 0;
    }

    /* Article snippet hover effects */
    .article-snippet {
      cursor: pointer;
      color: #333;
      text-decoration: none;
      display: block;
      padding: 8px 0;
    }
    .article-snippet:hover {
      color: #0d6efd;
      background-color: #f8f9fa;
    }
  </style>
</head>
<body>
  <!-- Navbar -->
  <nav class="navbar navbar-expand-lg navbar-dark bg-dark mb-4">
    <div class="container">
      <a class="navbar-brand d-flex align-items-center" href="{% url 'home' %}">
        <img src="{% static 'images/logo.png' %}" class="site-logo" alt="Logo">
        EarthLight Magazine
      </a>

      <div class="collapse navbar-collapse" id="navcoll">
        <ul class="navbar-nav ms-auto">
          {% if user.is_authenticated %}
            <li class="nav-item"><a class="nav-link" href="{% url 'create_article' %}">Submit Article</a></li>
            <li class="nav-item"><a class="nav-link" href="{% url 'upload_photo' %}">Upload Photo</a></li>
            <li class="nav-item"><a class="nav-link" href="{% url 'upload_video' %}">Upload Video</a></li>
            <li class="nav-item"><a class="nav-link" href="{% url 'account_logout' %}">Logout ({{ user.username }})</a></li>
          {% else %}
            <li class="nav-item"><a class="nav-link" href="{% url 'account_login' %}">Login</a></li>
            <li class="nav-item"><a class="nav-link" href="{% url 'account_signup' %}">Signup</a></li>
          {% endif %}
        </ul>
      </div>
    </div>
  </nav>
<nav class="navbar py-1" style="background-color: red;">
  <div class="container-fluid" style="text-align: center;">
    <a class="nav-link px-2" href="/about/" style="color: pink;">About</a>
    <a class="nav-link px-2" href="/article/2/" style="color: pink;">Featured Article</a>
    <a class="nav-link px-2" href="/selected_vids" style="color: pink;">Selected Videos</a>
    <a class="nav-link px-2" href="/fav_pics" style="color: pink;">Favorite Pics</a>
    <a class="nav-link px-2" href="/contact/" style="color: pink;">Contact Us!</a>
    <!-- Add more custom static links here -->
  </div>
</nav>

  <!-- Main content -->
  <main class="container">
    {% if messages %}
      {% for message in messages %}
        <div class="alert alert-{{ message.tags }} alert-dismissible fade show" role="alert">
          {{ message }}
          <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
      {% endfor %}
    {% endif %}

    {% block content %}{% endblock %}
  </main>

  <!-- Footer -->
  <footer class="text-center mt-4">
    &copy; {{ now|date:"Y" }} EarthLight Magazine and Member Web Blog
  </footer>

  <!-- Bootstrap JS -->
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
  {% block extra_scripts %}{% endblock %}
</body>
</html>
EOF

### HOME TEMPLATE
cat > "$PROJECT_DIR/templates/home.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2 class="text-center mb-4">Post Videos, Pics, and Write at EarthLight Magazine and Member Web Blog!</h2>

<div class="row">
  <!-- Articles column -->
  <div class="col-lg-3 col-md-4 mb-4">
    <h5>Latest Articles</h5>
    {% for article in articles %}
      <div class="card mb-3">
        {% if article.image %}
          <img src="{{ article.image.url }}" class="card-img-top" alt="{{ article.title }}" style="height:140px;">
        {% endif %}
        <div class="card-body p-2">
          <h6 class="card-title mb-2">{{ article.title }}</h6>
          <a href="{% url 'article_detail' article.pk %}" class="article-snippet">
            <div class="text-muted small">
              {{ article.content|striptags|truncatewords:30 }}
            </div>
          </a>
          {% if user == article.author %}
            <div class="mt-2">
              <a href="{% url 'edit_article' article.pk %}" class="btn btn-sm btn-warning">Edit</a>
              <a href="{% url 'delete_article' article.pk %}" class="btn btn-sm btn-danger" onclick="return confirm('Delete this article?');">Delete</a>
            </div>
          {% endif %}
          <p class="text-muted mt-2 mb-0"><small>By {{ article.author.username }} on {{ article.created|date:"M d, Y" }}</small></p>
        </div>
      </div>
    {% empty %}
      <p>No articles yet.</p>
    {% endfor %}

    {% if articles.has_other_pages %}
      <nav>
        <ul class="pagination justify-content-center">
          {% if articles.has_previous %}
            <li class="page-item"><a class="page-link" href="?page={{ articles.previous_page_number }}">Previous</a></li>
          {% endif %}
          <li class="page-item disabled"><span class="page-link">Page {{ articles.number }} of {{ articles.paginator.num_pages }}</span></li>
          {% if articles.has_next %}
            <li class="page-item"><a class="page-link" href="?page={{ articles.next_page_number }}">Next</a></li>
          {% endif %}
        </ul>
      </nav>
    {% endif %}
  </div>

  <!-- Videos column -->
  <div class="col-lg-6 col-md-8 mb-4">
    <h5 class="text-center">Recent Videos</h5>
    {% for video in videos %}
      <div class="card mb-4 video-card">
        <div class="ratio ratio-16x9">
          <video controls class="w-100" {% if video.thumbnail %} poster="{{ video.thumbnail.url }}" {% endif %}>
            <source src="{{ video.video.url }}" type="video/mp4">
            Your browser does not support the video tag.
          </video>
        </div>
        <div class="card-body p-2">
          <h6 class="card-title">{{ video.title }}</h6>
          <p class="text-muted"><small>By {{ video.uploader.username }} on {{ video.uploaded|date:"M d, Y" }}</small></p>
          {% if user == video.uploader %}
            <div class="mt-2">
              <a href="{% url 'video_delete' video.pk %}" class="btn btn-sm btn-danger" onclick="return confirm('Delete this video?');">Delete</a>
            </div>
          {% endif %}
        </div>
      </div>
    {% empty %}
      <p>No videos yet.</p>
    {% endfor %}
  </div>

  <!-- Photos column -->
  <div class="col-lg-3 col-md-12 mb-4">
    <h5>Recent Photos</h5>
    {% for photo in photos %}
      <div class="card mb-3">
        <img src="{{ photo.image.url }}" class="card-img-top" alt="{{ photo.caption }}" style="height:140px;">
        <div class="card-body p-2">
          <p class="card-text">{{ photo.caption }}</p>
          <p class="text-muted"><small>By {{ photo.uploader.username }} on {{ photo.uploaded|date:"M d, Y" }}</small></p>
          {% if user == photo.uploader %}
            <div class="mt-2">
              <a href="{% url 'delete_photo' photo.pk %}" class="btn btn-sm btn-danger" onclick="return confirm('Delete this photo?');">Delete Photo</a>
            </div>
          {% endif %}
        </div>
      </div>
    {% empty %}
      <p>No photos yet.</p>
    {% endfor %}
  </div>
</div>
{% endblock %}

EOF

### ARTICLE DETAIL TEMPLATE
cat > "$PROJECT_DIR/templates/article_detail.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="row justify-content-center">
  <div class="col-lg-8">
    <article>
      <h1 class="mb-3">{{ article.title }}</h1>
      
      {% if article.image %}
        <img src="{{ article.image.url }}" class="img-fluid mb-4" alt="{{ article.title }}">
      {% endif %}
      
      <div class="text-muted mb-3">
        <small>By {{ article.author.username }} on {{ article.created|date:"F d, Y" }}</small>
      </div>
      
      <div class="article-content">
        {{ article.content|safe }}
      </div>
      
      {% if user == article.author %}
        <div class="mt-4">
          <a href="{% url 'edit_article' article.pk %}" class="btn btn-warning">Edit Article</a>
          <a href="{% url 'delete_article' article.pk %}" class="btn btn-danger" onclick="return confirm('Delete this article?');">Delete Article</a>
        </div>
      {% endif %}
      
      <div class="mt-4">
        <a href="{% url 'home' %}" class="btn btn-secondary">Back to Home</a>
      </div>
    </article>
  </div>
</div>
{% endblock %}

EOF

### ARTICLE FORMS
cat > "$PROJECT_DIR/templates/create_article.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2>Create Article</h2>
<form method="post" enctype="multipart/form-data">
    {% csrf_token %}
    {{ form.media }}
    {{ form.as_p }}
    <button type="submit" class="btn btn-primary">Post Article</button>
    <a href="{% url 'home' %}" class="btn btn-secondary">Cancel</a>
</form>
{% endblock %}
EOF

cat > "$PROJECT_DIR/templates/edit_article.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2>Edit Article: {{ article.title }}</h2>
<form method="post" enctype="multipart/form-data">
    {% csrf_token %}
    {{ form.media }}
    {{ form.as_p }}
    <button type="submit" class="btn btn-primary">Save Changes</button>
    <a href="{% url 'home' %}" class="btn btn-secondary">Cancel</a>
</form>
{% endblock %}
EOF

### PHOTO UPLOAD
cat > "$PROJECT_DIR/templates/upload_photo.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2>Upload Photo</h2>
<form method="post" enctype="multipart/form-data">
    {% csrf_token %}
    {{ form.as_p }}
    <button type="submit" class="btn btn-primary">Upload</button>
    <a href="{% url 'home' %}" class="btn btn-secondary">Cancel</a>
</form>
{% endblock %}
EOF

### VIDEO UPLOAD
cat > "$PROJECT_DIR/templates/upload_video.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h2>Upload Video</h2>
<form method="post" enctype="multipart/form-data">
    {% csrf_token %}
    {{ form.as_p }}
    <button type="submit" class="btn btn-primary">Upload</button>
    <a href="{% url 'home' %}" class="btn btn-secondary">Cancel</a>
</form>
{% endblock %}
EOF

################################################################################
# STATIC PAGES
################################################################################

mkdir -p "$PROJECT_DIR/$APP_NAME/templates/static_pages"

# ABOUT PAGE
cat > "$PROJECT_DIR/$APP_NAME/templates/static_pages/about.html" << 'EOF'
{% extends "base.html" %}
{% load static %}
{% block content %}
<h1>About This Site</h1>
<p>This website was created instantly by a single bash file.</p>
<p>Django powers this site, it has data persistance from external backups.</p>
<p>It allows the logged in member to post Articles, Videos and Images!</p>
<p>If the website becomes corrupted or broken, running external_media_article.sh over again will fix it.</p>
<center><img src="{% static 'images/blue_blur.jpg' %}" alt="About photo"></center>
<pre>
This image file is at LiveshowSite/Static/images
~/better_Live/LiveShowSite/static/images 
</pre>
<p>Add a page to URLs.py to add a link.</p>
<p>Place each html page at the folder below:</p>
<p>~/better_Live/LiveShowSite/entertainment/templates/static_pages </p>
<iframe width="560" height="315" src="https://www.youtube.com/embed/r78H2JqD_eo?si=fkBBdYHcFtepSeZc" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
{% verbatim %}<pre># EarthLight Magazine — Build Script Overview (Final Version)

This document describes how the current Django build script for EarthLight Magazine works, including:
• What the script generates
• How backups are handled
• Where external folders live
• How recursion/disk growth is prevented
• What the finished site contains

This is a complete description of the new system.

# 1. High-Level Operation of the Script

Each time the script is run, it performs a full rebuild of the Django project:

/Users/blocky_mcblockface/better_Live/LiveShowSite

The script does the following:

1. Creates stable external directories for media and static files:
   /Users/blocky_mcblockface/better_Live/media
   /Users/blocky_mcblockface/better_Live/static

2. Creates and activates a virtual environment inside:
   LiveShowSite/venv

3. Installs required Python packages:
   Django, Django-Allauth, Django-CKEditor, MoviePy, Pillow

4. Generates the Django project and the entertainment app.
5. Creates all required Django files:
   - settings.py (with correct media/static paths)
   - models.py for Articles, Photos, Videos
   - forms.py, views.py, urls.py
   - CKEditor upload permission view
   - All templates (base, home, article detail, lists, upload forms, etc.)

6. Applies migrations.
7. Restores previous DB/media/static from backup if present.
8. Copies static files into the project’s internal static folder for convenience.
9. Runs collectstatic.
The result is a fully working, authenticated, media-enabled Django site.

# 2. Website Features Generated by the Script

## Articles
- Rich-text editing with CKEditor
- Optional image
- Pagination
- Full-page detail view
- Snippet preview system (iframe)
- Edit/delete support

## Photos
- Upload and display
- Stored in external media directory
- Delete with permission checks

## Videos
- Upload MP4 files
- Auto-generate thumbnail via ffmpeg/moviepy
- Optional custom thumbnail
- Displays with correct poster attribute

## Authentication (Allauth)
- Login, logout, registration
- Password reset
- Email verification
- Integrated Bootstrap templates

## Static Assets
- Logo, favicon, other images
- Served from external static directory
- Referenced via {% static %}

## CKEditor Integration
- Authenticated uploads only
- Uploads stored in external media directory
- Permission view enforces user.is_authenticated

# 3. Backup System (Safe, Non-Recursive)

The script uses a single stable location for backups:

/Users/blocky_mcblockface/better_Live/backups

It creates the following backups:

## Database:
backups/db_backup.sqlite3

## Media:
backups/media_backup/            (internal media from old project)
backups/media_backup_external/   (external user media)

## Static:
backups/static_backup_external/

## Safety
- Backups are NOT stored inside the project folder.
- The project folder is deleted before regeneration.
- No copy command ever targets a subfolder of its own destination.
- Therefore no recursive folder growth or disk explosion can occur.

# 4. External Folder Layout

All persistent data lives outside the project:

/Users/blocky_mcblockface/better_Live/
    media/
        video_thumbnails/
        videos/
        photos/
        uploads/ckeditor/
    static/
        images/
            favicon.ico
            favicon.png
            logo.png
    backups/

These folders survive every rebuild and remain untouched except for restoration.

# 5. External Paths Used by the Script

The only paths outside the project the script interacts with:

/Users/blocky_mcblockface/better_Live/media
/Users/blocky_mcblockface/better_Live/static
/Users/blocky_mcblockface/better_Live/backups

No other external locations are modified.

# 6. Summary

The build script provides a stable, safe, repeatable Django deployment:
- No recursion
- No runaway disk usage
- All backups safely located outside the project
- All media/static paths aligned
- Full site regeneration each run
- All user data preserved

This is the complete, up-to-date documentation of the new EarthLight Magazine script system.
</pre>
{% endverbatim %}
{% endblock %}

EOF

# CONTACT PAGE
cat > "$PROJECT_DIR/$APP_NAME/templates/static_pages/contact.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h1>Contact Us!</h1>
<p>Email me @ <a href="mailto: YOUR_USERNAME@yahoo.com">YOUR_USERNAME@yahoo.com</a></p>
{% endblock %}
EOF

# FEATURED ARTICLE (static page placeholder)
#cat > "$PROJECT_DIR/$APP_NAME/templates/static_pages/featured.html" << 'EOF'
#{% extends "base.html" %}
#{% block content %}
#<h2>Featured Article</h2>
#<p>This is the featured article page. Content coming soon.</p>
#{% endblock %}
#EOF
# in practice this is just a link in the second nav bar on base.html
#  <a class="nav-link px-2" href="/article/2/" style="color: pink;">Featured Article</a>

# SELECTED VIDEOS PAGE
cat > "$PROJECT_DIR/$APP_NAME/templates/static_pages/selected_vids.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
<h1><center>Selected Videos</center></h1>
<table style="border: none; border-collapse: collapse; width: 100%; text-align:center">
  <tr>
    <td style="border: none; padding: 0;">
      <!-- Video embed goes here -->
      <iframe width="560" height="315" src="https://www.youtube.com/embed/SesRWE02PIU?si=v7P6I3sir_rRFFXO" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
    </td>
  </tr>
  <tr>
    <td style="border: none; padding: 10px 0; text-align: left;">
      <strong style="font-size: 16px;">Weekend Update</strong>
    </td>
  </tr>
  <tr>
    <td style="border: none; padding: 0;">
      <!-- Video embed goes here -->
      <iframe width="560" height="315" src="https://www.youtube.com/embed/hkF1R0oe8OA?si=-FdiflfHm0hr6vST" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
    </td>
  </tr>
  <tr>
    <td style="border: none; padding: 10px 0; text-align: left;">
      <strong style="font-size: 16px;">Epstein White House Briefing Cold Open - SNL</strong>
    </td>
  </tr>
  <tr>
    <td style="border: none; padding: 0;">
     <iframe width="560" height="315" src="https://www.youtube.com/embed/QZK3S3-8HK8?si=dIaCP_xoK-hLO9y4" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
    </td>
  </tr>
  <tr>
    <td style="border: none; padding: 10px 0; text-align: left;">
      <strong style="font-size: 16px;">Trump is Lame!</strong>
    </td>
  </tr>
  <tr>
    <td style="border: none; padding: 0;">
    <iframe width="560" height="315" src="https://www.youtube.com/embed/3-mN-G7p0C8?si=IizbFOmgBysmefrU" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
    </td>
  </tr>
  <tr>
    <td style="border: none; padding: 10px 0; text-align: left;">
      <strong style="font-size: 16px;">Take me to Your Leader!</strong>
    </td>
  </tr>
  <tr>
    <td style="border: none; padding: 0;">
    <iframe width="560" height="315" src="https://www.youtube.com/embed/0D-lpcV9ZAg?si=emg5BjvkkGgCQjkw" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
    </td>
  </tr>
  <tr>
    <td style="border: none; padding: 10px 0; text-align: left;">
      <strong style="font-size: 16px;">Lawmakers Threatened with Death!</strong>
    </td>
  </tr>
</table>


{% endblock %}
EOF

# FAVOURITE PICS PAGE
cat > "$PROJECT_DIR/$APP_NAME/templates/static_pages/fav_pics.html" << 'EOF'
{% extends "base.html" %}
{% block content %}
{% load static %}
<h1>Favorite Pics </h1>
<p>
<img src="https://fastly.picsum.photos/id/2/367/267.jpg?hmac=fg7-2RVTv7Arg3KCcWEorOjdPaC-vJPKTLZgQ7f6R0g" title="hotlink to external host">
</p>
<p><img src="{% static 'images/blue_blur.jpg' %}" alt="About photo" title="static images"></p>
<p><img src="/media/photos/Tibet_Mount_Everest.jpg" width="100%" title="/media/photos...user submitted"></p>
{% endblock %}
EOF


################################################################################
# MIGRATIONS
################################################################################

echo "==> Running migrations..."
python manage.py makemigrations
python manage.py migrate

################################################################################
# RESTORE DB AND MEDIA (restore into EXTERNAL folders) - restore from LATEST backup
################################################################################

BACKUP_ROOT="$EXTERNAL_BASE/backups"

# Find the most recent timestamped backup
LATEST_BACKUP="$(ls -1d "$BACKUP_ROOT"/backup_* 2>/dev/null | sort | tail -n 1 || true)"

if [ -z "$LATEST_BACKUP" ]; then
    echo "==> No backups found in $BACKUP_ROOT, nothing to restore."
else
    echo "==> Restoring from backup: $LATEST_BACKUP"

    # Restore DB if exists in backup
    if [ -f "$LATEST_BACKUP/db_backup.sqlite3" ]; then
        echo "==> Restoring DB to project path"
        mkdir -p "$PROJECT_DIR"
        cp -p "$LATEST_BACKUP/db_backup.sqlite3" "$PROJECT_DIR/db.sqlite3"
    fi

    # Restore project media into external MEDIA_DIR
    if [ -d "$LATEST_BACKUP/project_media" ]; then
        echo "==> Restoring project-media into external MEDIA_DIR..."
        mkdir -p "$MEDIA_DIR"
        rsync -a --delete "$LATEST_BACKUP/project_media/" "$MEDIA_DIR/"
        chmod -R 755 "$MEDIA_DIR"
    fi

    # If an external media backup exists (merge/restore)
    if [ -d "$LATEST_BACKUP/media_external" ]; then
        echo "==> Restoring external-media backup into external MEDIA_DIR (merge)..."
        mkdir -p "$MEDIA_DIR"
        rsync -a --delete "$LATEST_BACKUP/media_external/" "$MEDIA_DIR/"
        chmod -R 755 "$MEDIA_DIR"
    fi

    # Restore external static if present in backups
    if [ -d "$LATEST_BACKUP/static_external" ]; then
        echo "==> Restoring external static folder..."
        mkdir -p "$STATIC_DIR"
        rsync -a --delete "$LATEST_BACKUP/static_external/" "$STATIC_DIR/"
        chmod -R 755 "$STATIC_DIR"
    fi
fi

echo "==> Collecting static files..."

python manage.py collectstatic --noinput
mkdir -p /Users/YOUR_USERNAME/better_Live/LiveShowSite/static
cp -r /Users/YOUR_USERNAME/better_Live/static/. /Users/blocky_mcblockface/better_Live/LiveShowSite/static/
echo "==> Setup complete. Run server with:"
echo "source $VENV_DIR/bin/activate && python manage.py runserver"

exit 0
